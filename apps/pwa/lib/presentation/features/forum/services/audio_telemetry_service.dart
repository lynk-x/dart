import 'package:lynk_x/presentation/features/forum/services/forum_audio_stream_service.dart';
import 'package:lynk_x/presentation/features/forum/services/stream_service.dart';

/// Centralized service providing real-time audio level telemetry
/// for both video broadcasts and audio calls.
class AudioTelemetryService {
  static final AudioTelemetryService _instance = AudioTelemetryService._internal();
  factory AudioTelemetryService() => _instance;
  AudioTelemetryService._internal();

  /// Gets current audio level (0.0 - 1.0) for active session (Video stream or Audio call)
  double getActiveAudioLevel({bool isSpeaking = true}) {
    if (ForumVideoStreamService().isLiveNotifier.value) {
      final level = ForumVideoStreamService().getAudioLevel();
      if (level > 0.0) return level;
    }

    final audioStreamLevel = ForumAudioStreamService().getAudioLevel();
    if (audioStreamLevel > 0.0) return audioStreamLevel;

    // Fallback baseline for visual indicator when participant is actively speaking
    return isSpeaking ? 0.45 : 0.0;
  }
}
