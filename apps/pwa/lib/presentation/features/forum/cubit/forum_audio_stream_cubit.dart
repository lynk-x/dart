import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/forum_audio_stream_service.dart';
import '../services/mini_overlay_service.dart';
import '../widgets/header.dart';
import 'forum_audio_stream_state.dart';

class ForumAudioStreamCubit extends Cubit<ForumAudioStreamState> {
  final ForumAudioStreamService service;
  final String forumId;
  final DateTime? forumCreatedAt;
  final String userId;
  String userName;
  final bool isOrganizer;

  /// Id of the social.forum_call_summaries row for the call this cubit is
  /// currently hosting — set by startAudioStream(), consumed by
  /// endAudioStream() to close it out. Null when not hosting, or when the
  /// insert itself failed (call-summary writes are best-effort, not
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
    // dropped listener connection gives up — surfaces it the same way
    // every other audio-stream failure reaches the user, via errorMessage.
    service.onRemoteAudioListenerLost(() {
      if (isClosed || state.role == ForumHeaderRole.host) return;
      emit(state.copyWith(
        errorMessage: 'Lost connection to the live call. Tap to rejoin.',
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

  /// Clears a one-shot error message after it's been shown to the user, so
  /// an identical subsequent failure (e.g. denying mic permission twice)
  /// still registers as a state change for listeners keyed on errorMessage.
  void clearAudioStreamError() {
    if (state.errorMessage == null) return;
    emit(state.copyWith(errorMessage: null));
  }

  Timer? _reconnectTimer;
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

          // Hosts lose their ability to broadcast start/end/speaker events
          // over this channel just like listeners lose their ability to
          // receive them — a disconnected host silently stops notifying
          // anyone the call ended, so this can't be listener-only.
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
      final isHost = hostId == userId;

      if (isLive) {
        if (!state.isLive) {
          service.configureMediaSession(
            title: 'Lynk-X Live Audio Stream',
            artist: isHost ? userName : 'Community Stream',
          );
          if (isHost) service.requestWakeLock();

          MiniOverlayService().activateLiveCall(hostName: isHost ? userName : 'Host');

          emit(state.copyWith(
            isLive: true,
            role: isHost ? ForumHeaderRole.host : ForumHeaderRole.listener,
            sessionId: sessionId,
            isMicMuted: !isHost,
            isBroadcastMuted: false,
          ));

          // The host's own publish flow already owns their peer connection
          // (startAudioStream); only a listener needs to pull the host's
          // track down. sessionId can be null here only if the host wrote
          // streaming_config before session creation resolved — nothing to
          // subscribe to yet in that case.
          if (!isHost && sessionId != null) {
            unawaited(service.subscribeToRemoteAudio(
              forumId: forumId,
              hostSessionId: sessionId,
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
          activeSpeakerNames: [],
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

  void _handleAudioEvent(Map<String, dynamic> payload) {
    final action = payload['action'] as String?;
    if (action == null) return;

    switch (action) {
      case 'start_stream':
        final sessionId = payload['sessionId'] as String?;
        final hostId = payload['hostId'] as String?;
        final hostName = payload['hostName'] as String?;
        final activeSpeakers = List<String>.from(payload['activeSpeakers'] ?? []);
        final isHost = hostId == userId;

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
          activeSpeakerNames: activeSpeakers,
          isMicMuted: !isHost,
          isBroadcastMuted: false,
        ));

        // The broadcaster's own startAudioStream() already owns publishing
        // its track; a listener needs to pull it down to actually hear it.
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

        emit(const ForumAudioStreamState(
          isLive: false,
          role: ForumHeaderRole.listener,
          activeSpeakerNames: [],
          isMicMuted: true,
          isBroadcastMuted: false,
        ));
        break;

      case 'speaker_update':
        final activeSpeakers = List<String>.from(payload['activeSpeakers'] ?? []);
        emit(state.copyWith(
          activeSpeakerNames: activeSpeakers,
        ));
        break;
    }
  }

  /// Joins an ongoing live audio call as a listener. Only reachable in the
  /// narrow window before the cubit's own auto-sync (_subscribeAndSyncState /
  /// _handleAudioEvent) has caught up — the Join Card disables its own tap
  /// target once state.isLive is true (see updates_tab.dart), which happens
  /// automatically the moment auto-sync resolves. Re-fetches streaming_config
  /// itself (rather than trusting a sessionId passed in — the caller, the
  /// Join Card, never has one) so the actual subscribe call below has a real
  /// session to pull from instead of emitting isLive:true with nothing
  /// behind it.
  Future<void> joinAudioStream({String? hostName}) async {
    if (state.isLive || _isJoiningOrStarting) return;
    _isJoiningOrStarting = true;

    try {
      final config = await service.fetchInitialStreamingConfig(forumId);
      if (isClosed || state.isLive) return;
      if (config == null || config['is_live'] != true) return;

      final sessionId = config['cf_session_id'] as String?;
      final hostId = config['active_host_id'] as String?;
      final isHost = hostId == userId;
      final hName = hostName ?? 'Host';

      service.configureMediaSession(
        title: 'Lynk-X Live Audio Stream',
        artist: isHost ? userName : hName,
      );
      MiniOverlayService().activateLiveCall(hostName: isHost ? userName : hName);
      emit(state.copyWith(
        isLive: true,
        role: isHost ? ForumHeaderRole.host : ForumHeaderRole.listener,
        sessionId: sessionId,
        isMicMuted: !isHost,
        isBroadcastMuted: false,
      ));

      if (!isHost && sessionId != null) {
        await service.subscribeToRemoteAudio(
          forumId: forumId,
          hostSessionId: sessionId,
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
          errorMessage: 'Microphone access is required to host a live audio stream.',
        ));
        return;
      }

      final sessionId = await service.createCloudflareSession(forumId);

      if (sessionId != null) {
        await service.publishCloudflareTracks(forumId, sessionId);
      }

      await service.updateForumStreamingConfig(
        forumId: forumId,
        isLive: true,
        sessionId: sessionId,
        hostId: userId,
      );

      final initialSpeakers = [userName];

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
        activeSpeakerNames: initialSpeakers,
        isMicMuted: false,
        isBroadcastMuted: false,
      ));

      // Broadcast start_stream to all connected attendees via WebSocket
      await service.broadcastAudioEvent(
        action: 'start_stream',
        sessionId: sessionId,
        hostId: userId,
        activeSpeakers: initialSpeakers,
        extraData: {'hostName': userName},
      );

      // Call-summary row — aggregate history only, not critical-path, so a
      // failure here doesn't roll back the call itself (already live for
      // everyone by this point). See ForumAudioStreamService.startCallSummary.
      final createdAt = forumCreatedAt;
      if (createdAt != null) {
        _callSummaryId = await service.startCallSummary(
          forumId: forumId,
          forumCreatedAt: createdAt,
          hostId: userId,
          sessionId: sessionId,
        );
      }
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
      // Server never learned the call ended: keep local state live (with the
      // mic already stopped, matching a muted host) instead of showing
      // "ended" locally while listeners and a later config fetch would still
      // see is_live: true — that mismatch was silently stranding listeners
      // and reviving the call out from under the host on their next visit.
      debugPrint('[ForumAudioStreamCubit] endAudioStream network sync error: $e');
      emit(state.copyWith(
        isMicMuted: true,
        errorMessage: 'Could not end the call — check your connection and try again.',
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
      activeSpeakerNames: [],
      isMicMuted: true,
      isBroadcastMuted: false,
    ));
  }

  /// Toggles local microphone mute/unmute state for speakers and host
  Future<void> toggleMic() async {
    if (_isTogglingMic) return;
    _isTogglingMic = true;

    try {
      final nextMuted = !state.isMicMuted;
      final currentSpeakers = List<String>.from(state.activeSpeakerNames);

      if (nextMuted) {
        // toggleMicEnabled (not stopLocalMicrophone) — if this is the host
        // and the track is actively published to Cloudflare, this swaps
        // the sender's track to null via replaceTrack() rather than
        // stopping the local MediaStreamTrack outright, which would kill
        // the Cloudflare publish for good (a later unmute's fresh track
        // from startLocalMicrophone() is never reattached to the
        // already-negotiated sender). No-op if nothing is published yet.
        await service.toggleMicEnabled(false);
        currentSpeakers.remove(userName);
      } else {
        // Only (re)acquire the mic if it isn't already captured — mute no
        // longer stops the local track (see toggleMicEnabled above), so on
        // a normal unmute it's still live and startLocalMicrophone() must
        // NOT be called again here: that function stops-and-replaces
        // whatever stream it's handed if one already exists, which would
        // kill the very track toggleMicEnabled(true) is about to resume
        // sending — turning this fix into the same bug one step later.
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
        if (!currentSpeakers.contains(userName)) {
          currentSpeakers.add(userName);
        }
        service.requestWakeLock();
      }

      emit(state.copyWith(
        isMicMuted: nextMuted,
        activeSpeakerNames: currentSpeakers,
      ));

      // Broadcast updated speaker list to all attendees via WebSocket
      await service.broadcastAudioEvent(
        action: 'speaker_update',
        hostId: userId,
        activeSpeakers: currentSpeakers,
      );
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

  @override
  Future<void> close() async {
    _reconnectTimer?.cancel();
    _telemetrySub?.cancel();
    _stopTelemetryPolling();
    service.removeListenerLostCallback();
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
