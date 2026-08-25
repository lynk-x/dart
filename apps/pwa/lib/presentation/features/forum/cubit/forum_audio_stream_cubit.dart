import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/forum_audio_stream_service.dart';
import '../services/pip_service.dart';
import '../widgets/forum_header.dart';
import 'forum_audio_stream_state.dart';

class ForumAudioStreamCubit extends Cubit<ForumAudioStreamState> {
  final ForumAudioStreamService service;
  final String forumId;
  final String userId;
  final String userName;
  final bool isOrganizer;

  ForumAudioStreamCubit({
    required this.service,
    required this.forumId,
    required this.userId,
    required this.userName,
    this.isOrganizer = false,
  }) : super(const ForumAudioStreamState());

  Timer? _reconnectTimer;

  /// Initializes Supabase Realtime channel subscription & initial state fetch
  Future<void> initRealtimeSubscription() async {
    await _subscribeAndSyncState();
  }

  Future<void> _subscribeAndSyncState() async {
    service.subscribeToAudioBroadcast(
      forumId: forumId,
      onEvent: _handleAudioEvent,
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

          StreamPipService().activateLiveCall(hostName: isHost ? userName : 'Host');

          emit(state.copyWith(
            isLive: true,
            role: isHost ? ForumHeaderRole.host : ForumHeaderRole.listener,
            sessionId: sessionId,
            isMicMuted: !isHost,
            isBroadcastMuted: false,
          ));
        }
      } else if (state.isLive && state.role != ForumHeaderRole.host) {
        // If stream explicitly ended according to config and we are not the active local host
        service.clearMediaSession();
        StreamPipService().endPipSession();

        emit(const ForumAudioStreamState(
          isLive: false,
          role: ForumHeaderRole.listener,
          activeSpeakerNames: [],
          isMicMuted: true,
          isBroadcastMuted: false,
        ));
      }
    }
  }

  void _handleAudioEvent(Map<String, dynamic> payload) {
    final action = payload['action'] as String?;
    if (action == null) return;

    switch (action) {
      case 'start_stream':
        final sessionId = payload['sessionId'] as String?;
        final hostId = payload['hostId'] as String?;
        final activeSpeakers = List<String>.from(payload['activeSpeakers'] ?? []);
        final isHost = hostId == userId;

        service.configureMediaSession(
          title: 'Lynk-X Live Audio Stream',
          artist: isHost ? userName : 'Community Stream',
        );

        StreamPipService().activateLiveCall(hostName: isHost ? userName : 'Host');

        emit(state.copyWith(
          isLive: true,
          role: isHost ? ForumHeaderRole.host : ForumHeaderRole.listener,
          sessionId: sessionId,
          activeSpeakerNames: activeSpeakers,
          isMicMuted: !isHost,
          isBroadcastMuted: false,
        ));
        break;

      case 'end_stream':
        service.clearMediaSession();
        StreamPipService().endPipSession();

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

  /// Starts a new live Audio Stream (Invoked by organizer/user double tap)
  Future<void> startAudioStream() async {
    if (state.isLive) return;

    try {
      final micGranted = await service.startLocalMicrophone();
      if (!micGranted) {
        emit(state.copyWith(
          errorMessage: 'Microphone access is required to host a live audio stream.',
        ));
        return;
      }

      final sessionId = await service.createCloudflareSession();

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

      StreamPipService().activateLiveCall(hostName: userName);

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
      );
    } catch (e) {
      service.stopLocalMicrophone();
      emit(state.copyWith(errorMessage: 'Failed to start audio stream: $e'));
    }
  }

  /// Ends an active Audio Stream (Invoked by host tapping stop button)
  Future<void> endAudioStream() async {
    if (!state.isLive) return;

    try {
      service.stopLocalMicrophone();
      service.clearMediaSession();
      await service.updateForumStreamingConfig(
        forumId: forumId,
        isLive: false,
      );

      StreamPipService().endPipSession();

      emit(const ForumAudioStreamState(
        isLive: false,
        role: ForumHeaderRole.listener,
        activeSpeakerNames: [],
        isMicMuted: true,
        isBroadcastMuted: false,
      ));

      // Broadcast end_stream to all connected attendees via WebSocket
      await service.broadcastAudioEvent(
        action: 'end_stream',
        hostId: userId,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to end audio stream: $e'));
    }
  }

  /// Toggles local microphone mute/unmute state for speakers and host
  Future<void> toggleMic() async {
    final nextMuted = !state.isMicMuted;
    final currentSpeakers = List<String>.from(state.activeSpeakerNames);

    if (nextMuted) {
      service.stopLocalMicrophone();
      currentSpeakers.remove(userName);
    } else {
      final micGranted = await service.startLocalMicrophone();
      if (!micGranted) {
        emit(state.copyWith(
          errorMessage: 'Microphone access is required to speak.',
        ));
        return;
      }
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
    service.stopLocalMicrophone();
    service.clearMediaSession();
    await service.unsubscribe();
    return super.close();
  }
}
