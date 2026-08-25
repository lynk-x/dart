import '../cubit/forum_audio_stream_cubit.dart';
import 'stream_service.dart';

class ParticipantMediaState {
  final String userId;
  final String name;
  final bool isMicMuted;
  final bool isCameraOn;
  final bool isSpeaking;

  const ParticipantMediaState({
    required this.userId,
    required this.name,
    this.isMicMuted = true,
    this.isCameraOn = false,
    this.isSpeaking = false,
  });
}

/// Centralized service for resolving participant media status (mic, camera, speaking)
/// across both audio calls and video broadcasts.
class StreamParticipantService {
  static final StreamParticipantService _instance = StreamParticipantService._internal();
  factory StreamParticipantService() => _instance;
  StreamParticipantService._internal();

  /// Resolves unified media state for a given user id and display name
  ParticipantMediaState resolveParticipantState({
    required String userId,
    required String userName,
    required String currentUserId,
    StreamParticipant? videoParticipant,
    ForumAudioStreamCubit? audioCubit,
    bool isStreamActive = false,
  }) {
    final isMe = userId == currentUserId;

    bool effectiveMicMuted = true;
    bool effectiveCameraOn = false;
    bool effectiveSpeaking = false;

    if (isStreamActive && videoParticipant != null) {
      effectiveMicMuted = videoParticipant.isMicMuted;
      effectiveCameraOn = videoParticipant.isCameraOn;
      effectiveSpeaking = videoParticipant.isSpeaking;
    } else if (audioCubit != null && audioCubit.state.isLive) {
      if (isMe) {
        effectiveMicMuted = audioCubit.state.isMicMuted;
      } else {
        final isSpeaker = audioCubit.state.activeSpeakerNames.contains(userName);
        effectiveMicMuted = !isSpeaker;
      }
      effectiveSpeaking = !effectiveMicMuted;
      effectiveCameraOn = false;
    }

    return ParticipantMediaState(
      userId: userId,
      name: userName,
      isMicMuted: effectiveMicMuted,
      isCameraOn: effectiveCameraOn,
      isSpeaking: effectiveSpeaking,
    );
  }

  /// Toggles mic status for participant across active media session
  void toggleMic({
    required String userId,
    required String currentUserId,
    ForumAudioStreamCubit? audioCubit,
  }) {
    if (userId == currentUserId && audioCubit != null && audioCubit.state.isLive) {
      audioCubit.toggleMic();
    } else {
      ForumVideoStreamService().toggleParticipantMic(userId, currentUserId: currentUserId);
    }
  }

  /// Toggles camera status for participant across active media session
  void toggleCamera({
    required String userId,
    required String currentUserId,
  }) {
    ForumVideoStreamService().toggleParticipantCamera(userId, currentUserId: currentUserId);
  }
}
