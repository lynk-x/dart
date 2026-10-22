import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;
import '../models/call_participant.dart';
import '../services/call_lifecycle_service.dart';
import '../services/call_recovery_service.dart';
import '../services/call_sound_service.dart';
import '../services/mini_overlay_service.dart';
import '../services/stream_service.dart';
import '../widgets/header.dart';
import 'forum_video_stream_state.dart';

/// Owns live video-call state for one forum — camera/mic/screen-share
/// lifecycle, participant registry, and publish/listener reconnection.
/// Mirrors [ForumAudioStreamCubit] field-for-field where the APIs align.
/// Each participant (host or co-host) runs its own instance against an
/// independent Cloudflare publish connection; see [_isPublishingRole].
class ForumVideoStreamCubit extends Cubit<ForumVideoStreamState> {
  final ForumVideoStreamService service;
  final String forumId;
  final DateTime? forumCreatedAt;
  final String userId;
  String userName;
  final bool isOrganizer;
  final String forumName;
  final String hostName;
  final bool isHost;

  /// Id of the social.forum_call_summaries row this cubit is hosting. Null
  /// when not hosting, or when the insert failed (best-effort, not
  /// critical-path — see ForumVideoStreamService.startCallSummary).
  String? _callSummaryId;

  static const String elementId = 'lynk_live_video_stage';
  static const String viewType = 'lynk-video-stage-view';
  static bool _viewRegistered = false;
  static web.HTMLVideoElement? _sharedVideoElement;

  // Fixed pool of pre-registered platform-view slots for co-hosts' video
  // tiles — matches GridStageOverlay's clamp(1, 4) (default
  // infra.system_config 'community'.max_call_speakers). Flutter web view
  // factories must be registered upfront, not dynamically per-userId, so
  // a fixed pool is allocated/reused instead.
  static const int maxParticipantSlots = 4;
  static const List<String> participantSlotViewTypes = [
    'lynk-video-participant-slot-0',
    'lynk-video-participant-slot-1',
    'lynk-video-participant-slot-2',
    'lynk-video-participant-slot-3',
  ];
  static bool _participantSlotsRegistered = false;
  static final List<web.HTMLVideoElement> participantSlotElements = [];
  // userId -> slot index, allocated as participants join, freed as they leave.
  final Map<String, int> participantSlotAssignment = {};

  web.HTMLVideoElement? videoElement;

  ForumVideoStreamCubit({
    required this.service,
    required this.forumId,
    this.forumCreatedAt,
    required this.userId,
    required this.userName,
    required this.forumName,
    required this.hostName,
    required this.isHost,
    this.isOrganizer = false,
  }) : super(ForumVideoStreamState(
          isMicMuted: !isHost,
          isCameraOn: isHost,
        )) {
    // Fires when the JS layer's bounded reconnect (3 attempts) for a
    // dropped listener connection gives up.
    service.onRemoteVideoListenerLost(() {
      if (isClosed || state.role == ForumHeaderRole.host) return;
      emit(state.copyWith(
        isListenerReconnecting: false,
        errorMessage: 'Lost connection to the live stream.',
      ));
    });

    // Each retry attempt (not yet exhausted) / eventual success — drives
    // a visible "Reconnecting…" state instead of leaving the UI silent
    // until either recovery or total failure.
    service.onRemoteVideoListenerReconnecting(
      onReconnected: () {
        if (isClosed) return;
        emit(state.copyWith(
            isListenerReconnecting: false, infoMessage: 'Reconnected'));
      },
    );

    // Publish-side counterpart: JS detected ICE failure/disconnect but
    // can't recover it itself — Cloudflare requires a new session, which
    // needs an authenticated create call, so the reconnect runs here.
    // CallRecoveryService owns the retry/backoff policy (3 attempts,
    // exponential backoff) so the video publish side matches the audio
    // side's recovery shape instead of firing once and giving up.
    CallRecoveryService().setPublishAction(RecoveryAction(_reconnectVideoPublish));
    service.onPublishNeedsReconnect(() {
      if (isClosed || !_isPublishingRole) return;
      unawaited(CallRecoveryService().requestReconnect(
        side: RecoverySide.publish,
        onGiveUp: () {
          if (isClosed) return;
          emit(state.copyWith(
            errorMessage: state.role == ForumHeaderRole.host
                ? 'Lost connection to your live stream. Please end and restart it.'
                : 'Lost connection to your speaking slot. Please rejoin as a speaker.',
          ));
        },
      ));
    });
    service.onPublishLost(() {
      if (isClosed || !_isPublishingRole) return;
      // The publish connection died outright (not a recoverable ICE
      // failure) — cancel any in-flight recovery so it doesn't fire
      // after the UI has already shown the give-up message, then surface
      // the same give-up text the recovery path would have.
      CallRecoveryService().cancel();
      emit(state.copyWith(
        errorMessage: state.role == ForumHeaderRole.host
            ? 'Lost connection to your live stream. Please end and restart it.'
            : 'Lost connection to your speaking slot. Please rejoin as a speaker.',
      ));
    });

    // Forward CallRecoveryService's recovery flag to the cubit's own
    // [isReconnecting] so the UI shows "Reconnecting…" during backoff.
    CallRecoveryService().isRecoveringNotifier.addListener(() {
      if (isClosed) return;
      emit(state.copyWith(
          isReconnecting: CallRecoveryService().isRecoveringNotifier.value));
    });
  }

  /// Whether this cubit instance owns the publish side of the peer
  /// connection — true for host and co-host alike; a listener never
  /// publishes.
  bool get _isPublishingRole =>
      state.role == ForumHeaderRole.host || state.role == ForumHeaderRole.speaker;

  /// Clears a one-shot error message after it's been shown, so an identical
  /// subsequent failure still registers as a state change.
  void clearVideoStreamError() {
    if (state.errorMessage == null) return;
    emit(state.copyWith(errorMessage: null));
  }

  void clearVideoStreamInfo() {
    if (state.infoMessage == null) return;
    emit(state.copyWith(infoMessage: null));
  }

  void updateUserName(String newName) {
    userName = newName;
  }

  /// Registers both the listener-side and publish-side JS connection
  /// callbacks unconditionally — a co-host is simultaneously a listener
  /// and a publisher, so both need to be live at once (role is checked
  /// inside each handler body, not at registration time).
  void registerConnectionCallbacks() {
    if (!kIsWeb) return;
    // Callbacks are registered on the service; the cubit listens to the
    // service's events and maps them to state emissions. The service
    // singleton manages the JS listeners, so registration here is a no-op
    // if already registered by another consumer — the service tracks
    // its listeners internally.
  }

  /// Recovers this user's publish connection after ICE failure/disconnect
  /// (host or co-host). Mirrors ForumAudioStreamCubit._reconnectPublish's
  /// reconnect/rebroadcast strategy exactly.
  ///
  /// Throws on any failure — CallRecoveryService's retry loop catches it
  /// and backs off exponentially up to 3 attempts. The recovery service
  /// owns the isReconnectingNotifier flag, so this method doesn't toggle
  /// state itself.
  Future<void> _reconnectVideoPublish() async {
    if (!state.isLive || !_isPublishingRole) {
      throw StateError('Not live or not a publishing role — refusing to reconnect.');
    }
    final fId = forumId;
    if (fId.isEmpty) {
      throw StateError('No forum id — refusing to reconnect.');
    }
    final isHostRole = state.role == ForumHeaderRole.host;

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) {
      throw StateError('No authenticated user — refusing to reconnect.');
    }

    // Cache the display name before any await — context.read across an
    // async gap is unsafe (the widget tree may have changed).
    final coHostUserName = isHostRole ? hostName : userName;

    final newSessionId = await service.createCloudflareSession(fId);
    if (isClosed) {
      // Hard stop — the cubit is gone and retrying would only waste attempts.
      throw RecoveryAbort('Cubit closed during session creation.');
    }
    if (newSessionId == null) {
      throw StateError('Could not create a new Cloudflare session.');
    }

    final published = await service.publishCloudflareStream(
      customSessionId: newSessionId,
      forceReconnect: true,
      trackBaseName: currentUserId,
    );
    if (isClosed) {
      throw RecoveryAbort('Cubit closed during track publish.');
    }
    if (!published) {
      throw StateError('Could not republish video tracks.');
    }

    final callSummaryId = _callSummaryId;
    if (isHostRole) {
      await service.updateForumStreamingConfig(
        forumId: fId,
        isLive: true,
        sessionId: newSessionId,
        hostId: currentUserId,
        callSummaryId: callSummaryId,
      );
      // The HOST's reconnected session is the new host session for
      // everyone, including the host's own Join Card instance — see
      // hostSessionIdNotifier's own comment.
      service.hostSessionIdNotifier.value = newSessionId;
    }
    if (callSummaryId != null) {
      await service.updateParticipantSession(
        callSummaryId: callSummaryId,
        cfSessionId: newSessionId,
        trackName: currentUserId,
      );
    }

    final selfParticipant = CallParticipant(
      userId: currentUserId,
      userName: coHostUserName,
      cfSessionId: newSessionId,
      trackName: currentUserId,
    );
    final updated = Map<String, CallParticipant>.from(state.participants);
    updated[currentUserId] = selfParticipant;
    emit(state.copyWith(sessionId: newSessionId, participants: updated));

    if (isHostRole) {
      await service.broadcastVideoEvent(
        action: 'session_changed',
        sessionId: newSessionId,
        hostId: currentUserId,
      );
    } else {
      await service.broadcastVideoEvent(
        action: 'participant_joined',
        extraData: selfParticipant.toBroadcastPayload(),
      );
    }
  }

  /// Initializes Supabase Realtime channel subscription & initial state fetch
  Future<void> initRealtimeSubscription() async {
    await _subscribeAndSyncState();
  }

  Future<void> _subscribeAndSyncState() async {
    service.subscribeToVideoBroadcast(
      forumId: forumId,
      onEvent: _handleVideoBroadcastEvent,
    );

    // Initial state check for active live stream when user opens the forum
    final config = await service.fetchInitialStreamingConfig(forumId);
    if (isClosed) return;

    if (config != null) {
      final isLive = config['is_live'] == true;
      final hostId = config['active_host_id'] as String?;
      final sessionId = config['cf_session_id'] as String?;
      final callSummaryId = config['call_summary_id'] as String?;
      final isHostUser = hostId == userId;

      if (isLive) {
        if (!state.isLive) {
          if (isHostUser) service.requestWakeLock();

          MiniOverlayService().activateLiveCall(hostName: isHostUser ? userName : hostName);

          // Every client's cubit needs this to support
          // joinAsVideoCoHost()/leaveVideoCoHost(), not just the host's.
          _callSummaryId = callSummaryId;

          // Bootstrap the registry — picks up co-hosts who joined before
          // this client opened the forum.
          final participants = callSummaryId != null
              ? await service.fetchCallParticipants(callSummaryId)
              : <String, CallParticipant>{};
          if (isClosed) return;

          emit(state.copyWith(
            isLive: true,
            role: isHostUser ? ForumHeaderRole.host : ForumHeaderRole.listener,
            sessionId: sessionId,
            participants: participants,
            isMicMuted: !isHostUser,
            isCameraOn: isHostUser,
            isFrontCamera: true,
            isScreenSharing: false,
          ));

          // Always a genuine discovery here (branch only runs while
          // state.isLive was false): opening the forum to find a call
          // already in progress. CallLifecycleService serialises the
          // chime, mic reporting, and telemetry start so they fire
          // exactly once.
          unawaited(CallLifecycleService().join());

          // Only a listener needs to pull the host's track down; the host's
          // own publish flow (startVideoStream) already owns its connection.
          if (!isHostUser && sessionId != null) {
            unawaited(service.subscribeToRemoteVideo(
              elementId: elementId,
              forumId: forumId,
              hostSessionId: sessionId,
            ));
          }
        }
      } else {
        // Stream explicitly not live according to config
        service.unsubscribeFromRemoteVideo();
    
        MiniOverlayService().endPipSession();

        emit(ForumVideoStreamState(
          isLive: false,
          role: ForumHeaderRole.listener,
          participants: const {},
          isMicMuted: true,
          isCameraOn: false,
          isFrontCamera: true,
          isScreenSharing: false,
        ));
      }
    } else if (state.isLive && state.role != ForumHeaderRole.host) {
      service.unsubscribeFromRemoteVideo();
  
      MiniOverlayService().endPipSession();
      emit(state.copyWith(isLive: false));
    }
  }

  void _handleVideoBroadcastEvent(Map<String, dynamic> payload) {
    final action = payload['action'] as String?;
    if (action == null) return;

    switch (action) {
      case 'start_stream':
        final sessionId = payload['sessionId'] as String?;
        final hostId = payload['hostId'] as String?;
        final hostName = payload['hostName'] as String?;
        final isHostUser = hostId == userId;

        if (!state.isLive) {
          service.requestWakeLock();
          MiniOverlayService().activateLiveCall(hostName: isHostUser ? userName : (hostName ?? this.hostName));

          _callSummaryId = payload['callSummaryId'] as String?;

          emit(state.copyWith(
            isLive: true,
            role: isHostUser ? ForumHeaderRole.host : ForumHeaderRole.listener,
            sessionId: sessionId,
            participants: state.participants,
            isMicMuted: !isHostUser,
            isCameraOn: isHostUser,
            isFrontCamera: true,
            isScreenSharing: false,
          ));

          // The host's own broadcast is echoed back — don't fire join side
          // effects again. Only a genuinely new listener joining an already-live
          // call needs the chime/mic-report/telemetry kick.
          if (!isHostUser) {
            unawaited(CallLifecycleService().join());
            if (sessionId != null) {
              unawaited(service.subscribeToRemoteVideo(
                elementId: elementId,
                forumId: forumId,
                hostSessionId: sessionId,
              ));
            }
          }
        }
        break;

      case 'end_stream':
        // _role == host means this is the host's own end-broadcast echoing
        // back to its sender — nothing further to do.
        if (state.role == ForumHeaderRole.host) return;
        service.unsubscribeFromRemoteVideo();
    
        MiniOverlayService().endPipSession();
        emit(ForumVideoStreamState(
          isLive: false,
          role: ForumHeaderRole.listener,
          participants: const {},
          isMicMuted: true,
          isCameraOn: false,
          isFrontCamera: true,
          isScreenSharing: false,
          infoMessage: 'The host ended the call.',
        ));
        // CallLifecycleService().leave() is idempotent — the host already
        // called it from their own end flow, so this is a no-op for them and
        // stops telemetry for everyone else.
        CallLifecycleService().leave();
        unawaited(CallSoundService.playEnd());
        break;

      case 'participant_joined':
        final participant = CallParticipant.fromJson(payload);
        if (participant.userId.isEmpty || participant.userId == userId) {
          break;
        }
        final updated = Map<String, CallParticipant>.from(state.participants);
        updated[participant.userId] = participant;
        emit(state.copyWith(participants: updated));
        break;

      case 'participant_left':
        final leftUserId = payload['userId'] as String?;
        if (leftUserId != null && leftUserId.isNotEmpty) {
          final updated = Map<String, CallParticipant>.from(state.participants)
            ..remove(leftUserId);
          emit(state.copyWith(participants: updated));
        }
        break;

      case 'participant_invite':
        final targetUserId = payload['targetUserId'] as String?;
        if (targetUserId != userId) break;
        final fromHostName = payload['fromHostName'] as String?;
        emit(state.copyWith(
            pendingInviteFromHostName: fromHostName ?? 'The host'));
        break;

      case 'participant_invite_accepted':
        if (state.role != ForumHeaderRole.host) break;
        unawaited(service.registerAcceptedVideoInvite(payload));
        break;

      case 'participant_invite_declined':
        if (state.role != ForumHeaderRole.host) break;
        final declinedUserId = payload['userId'] as String?;
        if (declinedUserId != null) {
          emit(state.copyWith(infoMessage: 'Invite declined'));
        }
        break;
    }
  }

  /// Starts a new live Video Stream (Invoked by organizer/user)
  Future<void> startVideoStream() async {
    if (state.isLive || service.isMinimizedNotifier.value) return;

    service.requestWakeLock();
    service.setLive(true);
    service.forumName = forumName;
    service.hostName = hostName;
    service.isHost = true;
    service.isMicMuted = state.isMicMuted;
    service.isCameraOn = state.isCameraOn;

    if (hostName.isNotEmpty) {
      service.updateHostSpeakerName(
        hostName,
        role: 'Host',
        isHostUser: true,
      );
    }

    if (videoElement != null) {
      videoElement!.style.transform = state.isFrontCamera ? 'scaleX(-1)' : 'none';
    }

    if (state.isCameraOn) {
      // The view is managed by the widget layer; this tells the service
      // to start the capture against the shared element.
      final success = await service.startVideoStream(elementId,
          isFrontCamera: state.isFrontCamera);
      if (!success) {
        emit(state.copyWith(
          isLive: false,
          errorMessage:
              'Camera permission requested or offline preview active',
        ));
        return;
      }
    } else {
      service.toggleCamera(false);
    }

    final sessionId = await service.createCloudflareSession(forumId);
    if (sessionId == null) {
      throw StateError(
          'Could not start your Cloudflare session — please try again.');
    }

    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? userId;

    final published = await service.publishCloudflareStream(
      customSessionId: sessionId,
      trackBaseName: currentUserId,
    );
    if (!published) {
      throw StateError('Could not publish your video — please try again.');
    }

    final createdAt = forumCreatedAt;
    if (createdAt == null) {
      throw StateError('forumCreatedAt is required to start a call.');
    }
    _callSummaryId = await service.startCallSummary(
      forumId: forumId,
      forumCreatedAt: createdAt,
      hostId: currentUserId,
      sessionId: sessionId,
    );
    final callSummaryId = _callSummaryId;
    if (callSummaryId == null) {
      throw StateError('Could not start the call — please try again.');
    }

    await service.joinAsCallParticipant(
      forumId: forumId,
      callSummaryId: callSummaryId,
      cfSessionId: sessionId,
      trackName: currentUserId,
    );

    await service.updateForumStreamingConfig(
      forumId: forumId,
      isLive: true,
      sessionId: sessionId,
      hostId: currentUserId,
      callSummaryId: callSummaryId,
    );

    service.hostSessionIdNotifier.value = sessionId;
    service.requestWakeLock();

    MiniOverlayService().activateLiveCall(hostName: userName);

    final hostParticipant = CallParticipant(
      userId: currentUserId,
      userName: userName,
      cfSessionId: sessionId,
      trackName: currentUserId,
    );

    emit(state.copyWith(
      isLive: true,
      role: ForumHeaderRole.host,
      sessionId: sessionId,
      participants: {hostParticipant.userId: hostParticipant},
      isMicMuted: state.isMicMuted,
      isCameraOn: state.isCameraOn,
      isFrontCamera: state.isFrontCamera,
      isScreenSharing: false,
    ));

    // CallLifecycleService serialises the chime, mic reporting, and
    // telemetry start so they fire exactly once.
    unawaited(CallLifecycleService().join());

    await service.broadcastVideoEvent(
      action: 'start_stream',
      sessionId: sessionId,
      hostId: currentUserId,
    );
  }

  /// Joins an ongoing live video call as a listener.
  Future<void> joinVideoStream({String? hostName}) async {
    if (state.isLive) return;

    service.requestWakeLock();
    service.setLive(true);
    service.forumName = forumName;
    service.hostName = hostName ?? this.hostName;
    service.isHost = false;
    service.isMicMuted = true;
    service.isCameraOn = false;

    if (videoElement != null) {
      videoElement!.style.transform = 'none';
    }

    final config = await service.fetchInitialStreamingConfig(forumId);
    if (isClosed) return;
    if (config == null || config['is_live'] != true) return;

    final sessionId = config['cf_session_id'] as String?;
    final hostId = config['active_host_id'] as String?;
    final callSummaryId = config['call_summary_id'] as String?;
    final isHostUser = hostId == userId;
    final hName = hostName ?? this.hostName;


    MiniOverlayService().activateLiveCall(hostName: isHostUser ? userName : hName);

    _callSummaryId = callSummaryId;

    final participants = callSummaryId != null
        ? await service.fetchCallParticipants(callSummaryId)
        : <String, CallParticipant>{};
    if (isClosed) return;

    emit(state.copyWith(
      isLive: true,
      role: isHostUser ? ForumHeaderRole.host : ForumHeaderRole.listener,
      sessionId: sessionId,
      participants: participants,
      isMicMuted: !isHostUser,
      isCameraOn: isHostUser,
      isFrontCamera: true,
      isScreenSharing: false,
    ));

    // Always a genuine join here — CallLifecycleService serialises the
    // chime, mic reporting, and telemetry start so they fire exactly once.
    unawaited(CallLifecycleService().join());

    if (!isHostUser && sessionId != null) {
      await service.subscribeToRemoteVideo(
        elementId: elementId,
        forumId: forumId,
        hostSessionId: sessionId,
      );
    }
  }

  /// Ends an active Video Stream (Invoked by host)
  Future<void> endVideoStream() async {
    if (!state.isLive) return;

    // Stop local video/camera hardware immediately
    try {
      service.stopVideoStream();
    } catch (_) {}

    try {
      await service.updateForumStreamingConfig(
        forumId: forumId,
        isLive: false,
      );
      await service.broadcastVideoEvent(
        action: 'end_stream',
        hostId: userId,
      );
    } catch (e) {
      debugPrint('[ForumVideoStreamCubit] endVideoStream network sync error: $e');
      emit(state.copyWith(
        errorMessage:
            'Could not end the call — check your connection and try again.',
      ));
      return;
    }


    MiniOverlayService().endPipSession();

    CallLifecycleService().leave();

    await service.endCallSummary(_callSummaryId);
    _callSummaryId = null;

    emit(ForumVideoStreamState(
      isLive: false,
      role: ForumHeaderRole.listener,
      participants: const {},
      isMicMuted: true,
      isCameraOn: false,
      isFrontCamera: true,
      isScreenSharing: false,
    ));
  }

  Future<void> toggleMic() async {
    final newMuted = !state.isMicMuted;
    emit(state.copyWith(isMicMuted: newMuted));
    service.isMicMuted = newMuted;
    service.toggleMic(!newMuted);
  }

  Future<void> toggleCamera() async {
    final newCameraOn = !state.isCameraOn;
    emit(state.copyWith(isCameraOn: newCameraOn));
    service.isCameraOn = newCameraOn;
    service.toggleCamera(newCameraOn);
  }

  Future<void> toggleScreenShare() async {
    if (state.isScreenSharing) {
      await service.startVideoStream(elementId,
          isFrontCamera: state.isFrontCamera);
      emit(state.copyWith(isScreenSharing: false));
    } else {
      final success = await service.startScreenShare(elementId);
      if (success) {
        emit(state.copyWith(isScreenSharing: true));
      }
    }
  }

  void switchCamera() {
    if (state.role == ForumHeaderRole.listener && !state.isCameraOn) return;
    try {
      service.switchCameraDevice(elementId, 'user');
    } catch (_) {}
    emit(state.copyWith(isFrontCamera: !state.isFrontCamera));
    if (videoElement != null) {
      videoElement!.style.transform =
          state.isFrontCamera ? 'scaleX(-1)' : 'none';
    }
  }

  Future<bool> joinAsVideoCoHost() async {
    if (state.role != ForumHeaderRole.listener) return false;
    if (state.pendingInviteFromHostName == null && !service.isMinimizedNotifier.value) {
      // Not strictly enforced, but mirror the invite flow expectation
    }

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return false;

      final callSummaryId = _callSummaryId;
      if (callSummaryId == null) return false;

      service.requestWakeLock();

      final sessionId = await service.createCloudflareSession(forumId);
      if (sessionId == null) return false;

      final published = await service.publishCloudflareStream(
        customSessionId: sessionId,
        trackBaseName: currentUserId,
      );
      if (!published) return false;

      await service.joinAsCallParticipant(
        forumId: forumId,
        callSummaryId: callSummaryId,
        cfSessionId: sessionId,
        trackName: currentUserId,
      );

      final selfParticipant = CallParticipant(
        userId: currentUserId,
        userName: userName,
        cfSessionId: sessionId,
        trackName: currentUserId,
      );
      service.requestWakeLock();

      emit(state.copyWith(
        role: ForumHeaderRole.speaker,
        isMicMuted: false,
        isCameraOn: true,
        isFrontCamera: true,
        participants: {
          ...state.participants,
          selfParticipant.userId: selfParticipant,
        },
      ));

      await service.broadcastVideoEvent(
        action: 'participant_invite_accepted',
        extraData: selfParticipant.toBroadcastPayload(),
      );
      return true;
    } catch (e) {
      debugPrint('[ForumVideoStreamCubit] joinAsVideoCoHost error: $e');
      emit(state.copyWith(
          errorMessage: 'Could not join as a speaker: $e'));
      return false;
    }
  }

  Future<void> leaveVideoCoHost() async {
    if (state.role != ForumHeaderRole.speaker) return;

    try {
      await service.leaveVideoCoHost();
    } catch (e) {
      debugPrint('[ForumVideoStreamCubit] leaveVideoCoHost error: $e');
    }

    emit(state.copyWith(
      role: ForumHeaderRole.listener,
      participants: Map<String, CallParticipant>.from(state.participants)
        ..remove(userId),
      isMicMuted: true,
      isCameraOn: false,
    ));
  }

  void declineVideoInvite() {
    if (state.pendingInviteFromHostName == null) return;
    service.declineVideoSpeakerInvite();
    emit(state.copyWith(clearPendingInvite: true));
  }

  Future<bool> acceptVideoInvite() async {
    if (state.pendingInviteFromHostName == null) return false;
    final success = await service.acceptVideoSpeakerInvite(
      viewerUserName: userName,
    );
    if (!isClosed) {
      emit(state.copyWith(clearPendingInvite: true));
    }
    return success;
  }

  @override
  Future<void> close() async {
    CallRecoveryService().cancel();
    CallLifecycleService().leave();
    service.removeListenerLostCallback();
    service.removeListenerReconnectingCallbacks();
    service.removePublishReconnectCallbacks();
    try {
      service.stopVideoStream();
    } catch (_) {}
    service.unsubscribeFromRemoteVideo();
    service.unsubscribeVideoBroadcast();

    MiniOverlayService().endPipSession();
    return super.close();
  }
}
