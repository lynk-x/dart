import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/forum_audio_stream_service.dart';
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

  /// Starts a new live Audio Stream (Invoked by organizer long press)
  Future<void> startAudioStream() async {
    if (state.isLive) return;

    try {
      final sessionId = await service.createCloudflareSession();

      await service.updateForumStreamingConfig(
        forumId: forumId,
        isLive: true,
        sessionId: sessionId,
        hostId: userId,
      );

      emit(state.copyWith(
        isLive: true,
        role: ForumHeaderRole.host,
        sessionId: sessionId,
        activeSpeakerNames: [userName],
        isMicMuted: false,
        isBroadcastMuted: false,
      ));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to start audio stream: $e'));
    }
  }

  /// Ends an active Audio Stream (Invoked by host tapping stop button)
  Future<void> endAudioStream() async {
    if (!state.isLive) return;

    try {
      await service.updateForumStreamingConfig(
        forumId: forumId,
        isLive: false,
      );

      emit(const ForumAudioStreamState(
        isLive: false,
        role: ForumHeaderRole.listener,
        activeSpeakerNames: [],
        isMicMuted: true,
        isBroadcastMuted: false,
      ));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to end audio stream: $e'));
    }
  }

  /// Toggles local microphone mute/unmute state for speakers and host
  void toggleMic() {
    final nextMuted = !state.isMicMuted;
    final currentSpeakers = List<String>.from(state.activeSpeakerNames);

    if (nextMuted) {
      currentSpeakers.remove(userName);
    } else if (!currentSpeakers.contains(userName)) {
      currentSpeakers.add(userName);
    }

    emit(state.copyWith(
      isMicMuted: nextMuted,
      activeSpeakerNames: currentSpeakers,
    ));
  }

  /// Toggles broadcast audio output mute/unmute state for listeners
  void toggleBroadcastMute() {
    emit(state.copyWith(
      isBroadcastMuted: !state.isBroadcastMuted,
    ));
  }
}
