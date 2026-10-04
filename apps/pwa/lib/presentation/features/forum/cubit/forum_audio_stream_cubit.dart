import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/call_participant.dart';
import '../services/call_sound_service.dart';
import '../services/forum_audio_stream_service.dart';
import '../services/mini_overlay_service.dart';
import '../widgets/header.dart';
import 'forum_audio_stream_state.dart';

/// Owns live audio-call state for one forum — mic/session lifecycle,
/// participant registry, and publish/listener reconnection. Each
/// participant (host or co-host) runs its own instance against an
/// independent Cloudflare publish connection; see [_isPublishingRole].
class ForumAudioStreamCubit extends Cubit<ForumAudioStreamState> {
  final ForumAudioStreamService service;
  final String forumId;
  final DateTime? forumCreatedAt;
  final String userId;
  String userName;
  final bool isOrganizer;

  /// Id of the social.forum_call_summaries row this cubit is hosting. Null
  /// when not hosting, or when the insert failed (best-effort, not
  /// critical-path — see ForumAudioStreamService.startCallSummary).
  String? _callSummaryId;

  ForumAudioStreamCubit({
    required this.service,
    required this.forumId,
    this.forumCreatedAt,
    required this.userId,
    required this.userName,
    this.isOrganizer = false,
  }) : super(const ForumAudioStreamState()) {
    // Fires when the JS layer's bounded reconnect (3 attempts) for a
    // dropped listener connection gives up.
    service.onRemoteAudioListenerLost(() {
      if (isClosed || state.role == ForumHeaderRole.host) return;
      emit(state.copyWith(
        isListenerReconnecting: false,
        errorMessage: 'Lost connection to the live call. Tap to rejoin.',
      ));
    });

    // Each retry attempt (not yet exhausted) / eventual success — drives
    // a visible "Reconnecting…" state instead of leaving the UI silent
    // until either recovery or total failure.
    service.onRemoteAudioListenerReconnecting(
      () {
        if (isClosed || state.role == ForumHeaderRole.host) return;
        emit(state.copyWith(isListenerReconnecting: true));
      },
      () {
        if (isClosed) return;
        emit(state.copyWith(
            isListenerReconnecting: false, infoMessage: 'Reconnected'));
      },
    );

    // Publish-side counterpart: JS detected ICE failure/disconnect but
    // can't recover it itself — Cloudflare requires a new session, which
    // needs an authenticated create call, so the reconnect runs here.
    service.onPublishNeedsReconnect(() {
      if (isClosed || !_isPublishingRole) return;
      unawaited(_reconnectPublish());
    });
    service.onPublishLost(() {
      if (isClosed || !_isPublishingRole) return;
      emit(state.copyWith(
        errorMessage: state.role == ForumHeaderRole.host
            ? 'Lost connection to your live call. Please end and restart it.'
            : 'Lost connection to your speaking slot. Please rejoin as a speaker.',
      ));
    });

    // React to isLive/role transitions from ANY of the several emit sites
    // (start_stream, initial sync, joinAudioStream, end_stream) rather than
    // threading timer start/stop calls through each one individually.
    _telemetrySub = stream.listen((s) {
      if (s.isLive && s.role != ForumHeaderRole.host) {
        _startTelemetryPolling();
      } else {
        _stopTelemetryPolling();
      }
    });
  }

  Timer? _telemetryTimer;
  StreamSubscription<ForumAudioStreamState>? _telemetrySub;

  void _startTelemetryPolling() {
    if (_telemetryTimer != null) return;
    _telemetryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      service.fetchListenerTelemetryStats();
    });
  }

  void _stopTelemetryPolling() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
  }

  void updateUserName(String newName) {
    userName = newName;
  }

  /// Clears a one-shot error message after it's been shown, so an identical
  /// subsequent failure still registers as a state change.
  void clearAudioStreamError() {
    if (state.errorMessage == null) return;
    emit(state.copyWith(errorMessage: null));
  }

  bool _isJoiningOrStarting = false;
  bool _isTogglingMic = false;

  /// Initializes Supabase Realtime channel subscription & initial state fetch
  Future<void> initRealtimeSubscription() async {
    await _subscribeAndSyncState();
  }

  Future<void> _subscribeAndSyncState() async {
    service.subscribeToAudioBroadcast(
      forumId: forumId,
      onEvent: _handleAudioEvent,
      onStatusChange: (status) {
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          if (!state.isLive) return;

          // Not listener-only: a disconnected host also loses the ability
          // to broadcast start/end/participant events over this channel.
          if (state.role != ForumHeaderRole.host) {
            service.unsubscribeFromRemoteAudio();
          }
          service.clearMediaSession();
          MiniOverlayService().endPipSession();
          emit(state.copyWith(
            isLive: false,
            errorMessage: state.role == ForumHeaderRole.host
                ? 'Connection lost. Your live call has ended — start a new one to continue.'
                : 'Audio stream disconnected.',
          ));
        }
      },
    );

    // Initial state check for active live stream when user opens the forum
    final config = await service.fetchInitialStreamingConfig(forumId);
    if (isClosed) return;

    if (config != null) {
      final isLive = config['is_live'] == true;
      final hostId = config['active_host_id'] as String?;
      final sessionId = config['cf_session_id'] as String?;
      final callSummaryId = config['call_summary_id'] as String?;
      final isHost = hostId == userId;

      if (isLive) {
        if (!state.isLive) {
          service.configureMediaSession(
            title: 'Lynk-X Live Audio Stream',
            artist: isHost ? userName : 'Community Stream',
          );
          if (isHost) service.requestWakeLock();

          MiniOverlayService()
              .activateLiveCall(hostName: isHost ? userName : 'Host');

          // Every client's cubit needs this to support
          // joinAsCoHost()/leaveCoHost(), not just the host's.
          _callSummaryId = callSummaryId;

          // Bootstrap the registry — picks up co-hosts who joined before
          // this client opened the forum.
          final participants = callSummaryId != null
              ? await service.fetchCallParticipants(callSummaryId)
              : <String, CallParticipant>{};
          if (isClosed) return;

          emit(state.copyWith(
            isLive: true,
            role: isHost ? ForumHeaderRole.host : ForumHeaderRole.listener,
            sessionId: sessionId,
            participants: participants,
            isMicMuted: !isHost,
            isBroadcastMuted: false,
          ));

          // Always a genuine discovery here (branch only runs while
          // state.isLive was false): opening the forum to find a call
          // already in progress.
          unawaited(CallSoundService.playJoin());

          // Only a listener needs to pull the host's track down; the host's
          // own publish flow (startAudioStream) already owns its connection.
          if (!isHost && sessionId != null) {
            unawaited(_pullAllParticipantTracks(
              hostSessionId: sessionId,
              participants: participants,
            ));
          }
        }
      } else {
        // Stream explicitly not live according to config
        service.unsubscribeFromRemoteAudio();
        service.clearMediaSession();
        MiniOverlayService().endPipSession();

        emit(const ForumAudioStreamState(
          isLive: false,
          role: ForumHeaderRole.listener,
          participants: {},
          isMicMuted: true,
          isBroadcastMuted: false,
        ));
      }
    } else if (state.isLive && state.role != ForumHeaderRole.host) {
      service.unsubscribeFromRemoteAudio();
      service.clearMediaSession();
      MiniOverlayService().endPipSession();
      emit(state.copyWith(isLive: false));
    }
  }

  /// Listener-only bootstrap: establishes the connection against the host's
  /// track first (which creates it), then adds every other active
  /// participant's track into that same connection — needed when a listener
  /// joins a call that already has co-hosts present.
  Future<void> _pullAllParticipantTracks({
    required String hostSessionId,
    required Map<String, CallParticipant> participants,
  }) async {
    final success = await service.subscribeToRemoteAudio(
      forumId: forumId,
      hostSessionId: hostSessionId,
    );
    if (isClosed || !success) return;

    for (final participant in participants.values) {
      if (participant.userId == userId) continue;
      // The host's track was already pulled above — skip it to avoid a
      // redundant/conflicting second pull of the same session.
      if (participant.cfSessionId == hostSessionId) continue;
      await service.addParticipantTrack(
        forumId: forumId,
        participantUserId: participant.userId,
        remoteSessionId: participant.cfSessionId,
        remoteTrackName: participant.trackName,
      );
    }
  }

  void _handleAudioEvent(Map<String, dynamic> payload) {
    final action = payload['action'] as String?;
    if (action == null) return;

    switch (action) {
      case 'start_stream':
        final sessionId = payload['sessionId'] as String?;
        final hostId = payload['hostId'] as String?;
        final hostName = payload['hostName'] as String?;
        final isHost = hostId == userId;
        // Captured before the emit below flips it to true — distinguishes
        // a genuine first join from the host's own reconnect echo
        // (_reconnectPublish also broadcasts start_stream for the same call).
        final wasAlreadyLive = state.isLive;
        // Not overwritten for the host's own instance — already set inside
        // startAudioStream() before this broadcast was sent.
        if (!isHost) {
          _callSummaryId = payload['callSummaryId'] as String?;
        }

        // Rides along on start_stream so a listener has the host's entry
        // immediately, without a separate fetchCallParticipants round trip.
        final hostParticipant = (hostId != null && sessionId != null)
            ? CallParticipant(
                userId: hostId,
                userName: hostName ?? 'Host',
                cfSessionId: sessionId,
                trackName: hostId,
              )
            : null;

        service.configureMediaSession(
          title: 'Lynk-X Live Audio Stream',
          artist: isHost ? userName : (hostName ?? 'Community Stream'),
        );

        MiniOverlayService().activateLiveCall(
          hostName: isHost ? userName : (hostName ?? 'Host'),
        );

        emit(state.copyWith(
          isLive: true,
          role: isHost ? ForumHeaderRole.host : ForumHeaderRole.listener,
          sessionId: sessionId,
          participants: hostParticipant != null
              ? {hostParticipant.userId: hostParticipant}
              : const {},
          isMicMuted: !isHost,
          isBroadcastMuted: false,
        ));

        // Only for a listener discovering the call just went live; the
        // host's own join sound plays from startAudioStream() instead.
        // !wasAlreadyLive excludes the host's own reconnect echo.
        if (!isHost && !wasAlreadyLive) {
          unawaited(CallSoundService.playJoin());
        }

        // The broadcaster already owns publishing its track; a listener
        // needs to pull it down to actually hear it.
        if (!isHost && sessionId != null) {
          unawaited(service.subscribeToRemoteAudio(
            forumId: forumId,
            hostSessionId: sessionId,
          ));
        }
        break;

      case 'end_stream':
        service.unsubscribeFromRemoteAudio();
        service.clearMediaSession();
        MiniOverlayService().endPipSession();

        // The host's own end echo also lands here; only attendees get the notice.
        emit(ForumAudioStreamState(
          isLive: false,
          role: ForumHeaderRole.listener,
          participants: const {},
          isMicMuted: true,
          isBroadcastMuted: false,
          infoMessage: state.role == ForumHeaderRole.host
              ? null
              : 'The host ended the call.',
        ));

        // The one call-lifecycle tone that's broadcast-driven rather than
        // local-only — everyone on the call hears it.
        unawaited(CallSoundService.playEnd());
        break;

      // A co-host joined the registry (the host's own join rides on
      // start_stream instead). Listeners pull the new participant's track;
      // other roles only need the registry update.
      case 'participant_joined':
        final participant = CallParticipant.fromJson(payload);
        if (participant.userId.isEmpty || participant.userId == userId) return;
        final updated = Map<String, CallParticipant>.from(state.participants);
        updated[participant.userId] = participant;
        emit(state.copyWith(participants: updated));

        if (state.role != ForumHeaderRole.host) {
          unawaited(service.addParticipantTrack(
            forumId: forumId,
            participantUserId: participant.userId,
            remoteSessionId: participant.cfSessionId,
            remoteTrackName: participant.trackName,
          ));
        }
        break;

      case 'participant_left':
        final leftUserId = payload['userId'] as String?;
        if (leftUserId == null || !state.participants.containsKey(leftUserId))
          return;
        final updated = Map<String, CallParticipant>.from(state.participants)
          ..remove(leftUserId);
        emit(state.copyWith(participants: updated));
        service.removeParticipantTrack(leftUserId);
        break;

      // Targeted at one user (payload['targetUserId']); every other
      // client's cubit also receives this (the channel is forum-wide, no
      // server-side per-recipient filtering) but ignores it. The host can't
      // publish a track on someone else's behalf, so this only notifies —
      // the actual publish happens in acceptSpeakerInvite(), self-initiated
      // by the invitee.
      case 'participant_invite':
        final targetUserId = payload['targetUserId'] as String?;
        if (targetUserId != userId) return;
        final fromHostName = payload['fromHostName'] as String?;
        emit(state.copyWith(
            pendingInviteFromHostName: fromHostName ?? 'The host'));
        break;

      // The invitee accepted and already published their track — host-only:
      // registers it via invite_speaker, then re-broadcasts
      // participant_joined so everyone converges on the same registry.
      case 'participant_invite_accepted':
        if (state.role != ForumHeaderRole.host) return;
        unawaited(_registerAcceptedInvite(payload));
        break;
    }
  }

  Future<void> _registerAcceptedInvite(Map<String, dynamic> payload) async {
    final callSummaryId = _callSummaryId;
    if (callSummaryId == null) return;
    final participant = CallParticipant.fromJson(payload);
    if (participant.userId.isEmpty) return;

    final participantId = await service.inviteCallParticipant(
      forumId: forumId,
      callSummaryId: callSummaryId,
      targetUserId: participant.userId,
      cfSessionId: participant.cfSessionId,
      trackName: participant.trackName,
    );
    if (participantId == null) {
      // Cap was hit or some other rejection — surface it to the inviter
      // rather than silently dropping it.
      emit(state.copyWith(
          errorMessage:
              'Could not add ${participant.userName} as a speaker — the call may be full.'));
      return;
    }

    final updated = Map<String, CallParticipant>.from(state.participants);
    updated[participant.userId] = participant;
    emit(state.copyWith(participants: updated));

    await service.broadcastAudioEvent(
      action: 'participant_joined',
      extraData: participant.toBroadcastPayload(),
    );
  }

  /// Accepts a pending "invited to speak" prompt, running the same publish
  /// sequence [joinAsCoHost] does, but reports success back to the host via
  /// participant_invite_accepted rather than calling join_as_call_participant
  /// directly — only the inviting host can register a non-organizer member.
  Future<bool> acceptSpeakerInvite() async {
    if (state.pendingInviteFromHostName == null || _isJoiningAsCoHost) {
      return false;
    }
    _isJoiningAsCoHost = true;
    try {
      emit(state.copyWith(clearPendingInvite: true));

      final micGranted = await service.startLocalMicrophone();
      if (!micGranted) {
        emit(state.copyWith(
            errorMessage: 'Microphone access is required to speak.'));
        return false;
      }

      final sessionId = await service.createCloudflareSession(forumId);
      if (sessionId == null) {
        emit(state.copyWith(
            errorMessage:
                'Could not start your speaker session — please try again.'));
        return false;
      }

      final published = await service
          .publishCloudflareTracks(forumId, sessionId, trackName: userId);
      if (!published) {
        emit(state.copyWith(
            errorMessage: 'Could not publish your audio — please try again.'));
        return false;
      }

      final selfParticipant = CallParticipant(
        userId: userId,
        userName: userName,
        cfSessionId: sessionId,
        trackName: userId,
      );

      emit(state.copyWith(role: ForumHeaderRole.speaker, isMicMuted: false));
      service.requestWakeLock();

      await service.broadcastAudioEvent(
        action: 'participant_invite_accepted',
        extraData: selfParticipant.toBroadcastPayload(),
      );
      return true;
    } catch (e) {
      debugPrint('[ForumAudioStreamCubit] acceptSpeakerInvite error: $e');
      emit(state.copyWith(errorMessage: 'Could not join as a speaker: $e'));
      return false;
    } finally {
      _isJoiningAsCoHost = false;
    }
  }

  void declineSpeakerInvite() {
    if (state.pendingInviteFromHostName == null) return;
    emit(state.copyWith(clearPendingInvite: true));
  }

  /// Host/organizer-only — sends a "you're invited to speak" prompt to
  /// [targetUserId]. Does not itself grant a speaking slot; only the
  /// invitee's own acceptSpeakerInvite() publishes their track.
  Future<void> inviteSpeaker(String targetUserId) async {
    if (state.role != ForumHeaderRole.host) return;
    await service.broadcastAudioEvent(
      action: 'participant_invite',
      extraData: {'targetUserId': targetUserId, 'fromHostName': userName},
    );
  }

  /// Joins an ongoing live audio call as a listener. Only reachable in the
  /// narrow window before the cubit's own auto-sync has caught up — the
  /// Join Card disables its tap target once state.isLive is true.
  /// Re-fetches streaming_config itself rather than trusting a passed-in
  /// sessionId, so the subscribe call below has a real session to pull from.
  Future<void> joinAudioStream({String? hostName}) async {
    if (state.isLive || _isJoiningOrStarting) return;
    _isJoiningOrStarting = true;

    try {
      final config = await service.fetchInitialStreamingConfig(forumId);
      if (isClosed || state.isLive) return;
      if (config == null || config['is_live'] != true) return;

      final sessionId = config['cf_session_id'] as String?;
      final hostId = config['active_host_id'] as String?;
      final callSummaryId = config['call_summary_id'] as String?;
      final isHost = hostId == userId;
      final hName = hostName ?? 'Host';

      service.configureMediaSession(
        title: 'Lynk-X Live Audio Stream',
        artist: isHost ? userName : hName,
      );
      MiniOverlayService()
          .activateLiveCall(hostName: isHost ? userName : hName);

      _callSummaryId = callSummaryId;

      final participants = callSummaryId != null
          ? await service.fetchCallParticipants(callSummaryId)
          : <String, CallParticipant>{};
      if (isClosed || state.isLive) return;

      emit(state.copyWith(
        isLive: true,
        role: isHost ? ForumHeaderRole.host : ForumHeaderRole.listener,
        sessionId: sessionId,
        participants: participants,
        isMicMuted: !isHost,
        isBroadcastMuted: false,
      ));

      // Always a genuine join here, never a resync echo (state.isLive was
      // checked false at entry and again just above).
      unawaited(CallSoundService.playJoin());

      if (!isHost && sessionId != null) {
        await _pullAllParticipantTracks(
          hostSessionId: sessionId,
          participants: participants,
        );
      }
    } finally {
      _isJoiningOrStarting = false;
    }
  }

  /// Starts a new live Audio Stream (Invoked by organizer/user double tap)
  Future<void> startAudioStream() async {
    if (state.isLive || _isJoiningOrStarting) return;
    _isJoiningOrStarting = true;

    try {
      final micGranted = await service.startLocalMicrophone();
      if (!micGranted) {
        MiniOverlayService().endPipSession();
        emit(state.copyWith(
          isLive: false,
          errorMessage:
              'Microphone access is required to host a live audio stream.',
        ));
        return;
      }

      final sessionId = await service.createCloudflareSession(forumId);
      if (sessionId == null) {
        throw StateError(
            'Could not start your Cloudflare session — please try again.');
      }

      final published = await service
          .publishCloudflareTracks(forumId, sessionId, trackName: userId);
      if (!published) {
        throw StateError('Could not publish your audio — please try again.');
      }

      // Must exist before joinAsCallParticipant (needs its id) and before
      // updateForumStreamingConfig (carries it for later clients to
      // discover) — a failure here aborts the start.
      final createdAt = forumCreatedAt;
      if (createdAt == null) {
        throw StateError('forumCreatedAt is required to start a call.');
      }
      _callSummaryId = await service.startCallSummary(
        forumId: forumId,
        forumCreatedAt: createdAt,
        hostId: userId,
        sessionId: sessionId,
      );
      final callSummaryId = _callSummaryId;
      if (callSummaryId == null) {
        throw StateError('Could not start the call — please try again.');
      }

      // The host claims their own slot the same way a co-host does —
      // there's no separate host-registration path.
      await service.joinAsCallParticipant(
        forumId: forumId,
        callSummaryId: callSummaryId,
        cfSessionId: sessionId,
        trackName: userId,
      );

      await service.updateForumStreamingConfig(
        forumId: forumId,
        isLive: true,
        sessionId: sessionId,
        hostId: userId,
        callSummaryId: callSummaryId,
      );

      final hostParticipant = CallParticipant(
        userId: userId,
        userName: userName,
        cfSessionId: sessionId,
        trackName: userId,
      );

      service.configureMediaSession(
        title: 'Lynk-X Live Audio Stream',
        artist: '$userName (Host)',
      );
      service.requestWakeLock();

      MiniOverlayService().activateLiveCall(hostName: userName);

      emit(state.copyWith(
        isLive: true,
        role: ForumHeaderRole.host,
        sessionId: sessionId,
        participants: {hostParticipant.userId: hostParticipant},
        isMicMuted: false,
        isBroadcastMuted: false,
      ));

      // Fires immediately for the host rather than waiting for the
      // broadcast below to round-trip back through _handleAudioEvent.
      unawaited(CallSoundService.playJoin());

      // Carries the host's CallParticipant so a listener can seed its
      // registry without a separate fetch, and callSummaryId so
      // joinAsCoHost()/leaveCoHost() work for already-watching clients.
      await service.broadcastAudioEvent(
        action: 'start_stream',
        sessionId: sessionId,
        hostId: userId,
        extraData: {'hostName': userName, 'callSummaryId': callSummaryId},
      );
    } catch (e) {
      service.stopLocalMicrophone();
      service.clearMediaSession();
      MiniOverlayService().endPipSession();
      emit(state.copyWith(
        isLive: false,
        errorMessage: 'Failed to start audio stream: $e',
      ));
    } finally {
      _isJoiningOrStarting = false;
    }
  }

  /// Ends an active Audio Stream (Invoked by host tapping stop button)
  Future<void> endAudioStream() async {
    if (!state.isLive) return;

    // Stop local audio hardware immediately — no reason to keep the mic hot
    // while the network call below is in flight.
    service.stopLocalMicrophone();

    try {
      await service.updateForumStreamingConfig(
        forumId: forumId,
        isLive: false,
      );

      // Broadcast end_stream to all connected attendees via WebSocket
      await service.broadcastAudioEvent(
        action: 'end_stream',
        hostId: userId,
      );
    } catch (e) {
      // Server never learned the call ended: keep local state live (mic
      // already stopped, matching a muted host) rather than show "ended"
      // locally while is_live: true still strands listeners server-side.
      debugPrint(
          '[ForumAudioStreamCubit] endAudioStream network sync error: $e');
      emit(state.copyWith(
        isMicMuted: true,
        errorMessage:
            'Could not end the call — check your connection and try again.',
      ));
      return;
    }

    service.clearMediaSession();
    MiniOverlayService().endPipSession();

    await service.endCallSummary(_callSummaryId);
    _callSummaryId = null;

    emit(const ForumAudioStreamState(
      isLive: false,
      role: ForumHeaderRole.listener,
      participants: {},
      isMicMuted: true,
      isBroadcastMuted: false,
    ));
  }

  /// Toggles local microphone mute/unmute. Doesn't touch the participant
  /// registry — holding a slot and being audibly unmuted are separate
  /// concerns; muting only silences the published track via
  /// toggleMicEnabled's replaceTrack swap.
  Future<void> toggleMic() async {
    if (_isTogglingMic) return;
    _isTogglingMic = true;

    try {
      final nextMuted = !state.isMicMuted;

      if (nextMuted) {
        // toggleMicEnabled, not stopLocalMicrophone: swaps the sender's
        // track to null via replaceTrack() rather than stopping the local
        // MediaStreamTrack outright, which would kill the Cloudflare
        // publish for good. No-op if nothing is published yet.
        await service.toggleMicEnabled(false);
      } else {
        // Only (re)acquire if not already captured — calling
        // startLocalMicrophone() again would stop-and-replace the already
        // live track toggleMicEnabled(true) is about to resume sending.
        if (!service.hasLocalMicrophone) {
          final micGranted = await service.startLocalMicrophone();
          if (!micGranted) {
            emit(state.copyWith(
              errorMessage: 'Microphone access is required to speak.',
            ));
            return;
          }
        }
        await service.toggleMicEnabled(true);
        service.requestWakeLock();
      }

      emit(state.copyWith(isMicMuted: nextMuted));
    } finally {
      _isTogglingMic = false;
    }
  }

  /// Toggles broadcast audio output mute/unmute state for listeners
  void toggleBroadcastMute() {
    final nextMuted = !state.isBroadcastMuted;
    service.setBroadcastMuted(nextMuted);
    emit(state.copyWith(
      isBroadcastMuted: nextMuted,
    ));
  }

  bool _isJoiningAsCoHost = false;

  /// Self-serve: an eligible organizer (not the original host) joins the
  /// call as a co-host. Mirrors startAudioStream's publish sequence (mic ->
  /// session -> publish -> join_as_call_participant) but doesn't touch
  /// streaming_config — this user is an additional participant, not a
  /// replacement for the host.
  Future<bool> joinAsCoHost() async {
    if (_isJoiningAsCoHost ||
        !state.isLive ||
        state.role == ForumHeaderRole.host) {
      return false;
    }
    final callSummaryId = _callSummaryId;
    if (callSummaryId == null) {
      emit(state.copyWith(
          errorMessage: 'Could not join — call details are still loading.'));
      return false;
    }

    _isJoiningAsCoHost = true;
    try {
      final micGranted = await service.startLocalMicrophone();
      if (!micGranted) {
        emit(state.copyWith(
            errorMessage:
                'Microphone access is required to join as a speaker.'));
        return false;
      }

      final sessionId = await service.createCloudflareSession(forumId);
      if (sessionId == null) {
        emit(state.copyWith(
            errorMessage:
                'Could not start your speaker session — please try again.'));
        return false;
      }

      final published = await service
          .publishCloudflareTracks(forumId, sessionId, trackName: userId);
      if (!published) {
        emit(state.copyWith(
            errorMessage: 'Could not publish your audio — please try again.'));
        return false;
      }

      final participantId = await service.joinAsCallParticipant(
        forumId: forumId,
        callSummaryId: callSummaryId,
        cfSessionId: sessionId,
        trackName: userId,
      );
      if (participantId == null) {
        service.stopLocalMicrophone();
        emit(state.copyWith(
            errorMessage:
                'This call already has the maximum number of speakers.'));
        return false;
      }

      final selfParticipant = CallParticipant(
        userId: userId,
        userName: userName,
        cfSessionId: sessionId,
        trackName: userId,
      );
      final updatedParticipants =
          Map<String, CallParticipant>.from(state.participants);
      updatedParticipants[userId] = selfParticipant;

      emit(state.copyWith(
        role: ForumHeaderRole.speaker,
        participants: updatedParticipants,
        isMicMuted: false,
      ));
      service.requestWakeLock();

      await service.broadcastAudioEvent(
        action: 'participant_joined',
        extraData: selfParticipant.toBroadcastPayload(),
      );

      return true;
    } catch (e) {
      debugPrint('[ForumAudioStreamCubit] joinAsCoHost error: $e');
      emit(state.copyWith(errorMessage: 'Could not join as a speaker: $e'));
      return false;
    } finally {
      _isJoiningAsCoHost = false;
    }
  }

  /// Self-serve: a co-host (not the original host — they use
  /// endAudioStream) leaves their speaking slot.
  Future<void> leaveCoHost() async {
    if (state.role != ForumHeaderRole.speaker) return;
    final callSummaryId = _callSummaryId;

    service.stopLocalMicrophone();
    service.releaseWakeLock();

    if (callSummaryId != null) {
      await service.leaveCallParticipant(callSummaryId);
    }

    final updatedParticipants =
        Map<String, CallParticipant>.from(state.participants)..remove(userId);
    emit(state.copyWith(
      role: ForumHeaderRole.listener,
      participants: updatedParticipants,
      isMicMuted: true,
    ));

    await service.broadcastAudioEvent(
      action: 'participant_left',
      extraData: {'userId': userId},
    );
  }

  bool _isReconnectingPublish = false;

  /// Whether this cubit instance owns the publish side of the peer
  /// connection — true for host and co-host alike; a listener never
  /// publishes.
  bool get _isPublishingRole =>
      state.role == ForumHeaderRole.host ||
      state.role == ForumHeaderRole.speaker;

  /// Recovers this user's publish connection after ICE failure/disconnect.
  /// Cloudflare has no supported same-session recovery for a publisher, so
  /// this replaces it entirely: new session, republished tracks, persisted
  /// to this user's forum_call_participants row. The host additionally owns
  /// streaming_config.cf_session_id (the address every listener's base
  /// connection was built against), so only the host's reconnect updates it
  /// and broadcasts 'start_stream' to rebuild listener connections; a
  /// co-host's reconnect instead re-broadcasts 'participant_joined' so
  /// already-connected listeners just re-pull that one track.
  Future<void> _reconnectPublish() async {
    if (_isReconnectingPublish || !state.isLive || !_isPublishingRole) {
      return;
    }
    final isHost = state.role == ForumHeaderRole.host;
    final callSummaryId = _callSummaryId;
    _isReconnectingPublish = true;
    emit(state.copyWith(isReconnecting: true));
    try {
      final newSessionId = await service.createCloudflareSession(forumId);
      if (isClosed || newSessionId == null) return;

      final published = await service.publishCloudflareTracks(
        forumId,
        newSessionId,
        forceReconnect: true,
        trackName: userId,
      );
      if (isClosed || !published) return;

      if (isHost) {
        await service.updateForumStreamingConfig(
          forumId: forumId,
          isLive: true,
          sessionId: newSessionId,
          hostId: userId,
          callSummaryId: callSummaryId,
        );
      }
      if (callSummaryId != null) {
        await service.updateParticipantSession(
          callSummaryId: callSummaryId,
          cfSessionId: newSessionId,
          trackName: userId,
        );
      }
      if (isClosed) return;

      final updatedParticipants =
          Map<String, CallParticipant>.from(state.participants);
      final selfParticipant = CallParticipant(
        userId: userId,
        userName: userName,
        cfSessionId: newSessionId,
        trackName: userId,
      );
      updatedParticipants[userId] = selfParticipant;
      emit(state.copyWith(
          sessionId: newSessionId, participants: updatedParticipants));

      if (isHost) {
        await service.broadcastAudioEvent(
          action: 'start_stream',
          sessionId: newSessionId,
          hostId: userId,
          extraData: {'hostName': userName, 'callSummaryId': callSummaryId},
        );
      } else {
        await service.broadcastAudioEvent(
          action: 'participant_joined',
          extraData: selfParticipant.toBroadcastPayload(),
        );
      }
    } catch (e) {
      debugPrint('[ForumAudioStreamCubit] _reconnectPublish error: $e');
    } finally {
      _isReconnectingPublish = false;
      if (!isClosed) emit(state.copyWith(isReconnecting: false));
    }
  }

  @override
  Future<void> close() async {
    _telemetrySub?.cancel();
    _stopTelemetryPolling();
    service.removeListenerLostCallback();
    service.removeListenerReconnectingCallbacks();
    service.removePublishReconnectCallbacks();
    service.stopLocalMicrophone();
    if (state.role != ForumHeaderRole.host) {
      service.unsubscribeFromRemoteAudio();
    }
    service.clearMediaSession();
    MiniOverlayService().endPipSession();
    await service.unsubscribe();
    return super.close();
  }
}
