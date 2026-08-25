import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:lynk_x/presentation/features/forum/services/forum_audio_stream_service.dart';
import 'package:lynk_x/presentation/features/forum/services/stream_service.dart';

/// Centralized service providing real-time audio level telemetry
/// for both video broadcasts and audio calls.
///
/// Exposes a [levelNotifier] `ValueNotifier<double>` that is updated
/// on a shared 80ms polling timer — widgets subscribe to this notifier
/// rather than each spinning their own timers.
class AudioTelemetryService {
  static final AudioTelemetryService _instance = AudioTelemetryService._internal();
  factory AudioTelemetryService() => _instance;
  AudioTelemetryService._internal();

  /// Shared audio level notifier (0.0–1.0) driven by the singleton polling timer.
  /// Widgets should listen to this rather than calling [getActiveAudioLevel] on their own timers.
  final ValueNotifier<double> levelNotifier = ValueNotifier(0.0);

  Timer? _pollingTimer;
  int _listenerCount = 0;

  /// Gets the current audio level synchronously (0.0–1.0) for the active session.
  double getActiveAudioLevel() {
    if (ForumVideoStreamService().isLiveNotifier.value) {
      final level = ForumVideoStreamService().getAudioLevel();
      if (level > 0.0) return level;
    }
    final audioStreamLevel = ForumAudioStreamService().getAudioLevel();
    if (audioStreamLevel > 0.0) return audioStreamLevel;
    return 0.0;
  }

  /// Starts the shared polling timer. Call once per consumer that needs the notifier.
  /// The timer is ref-counted and starts only on the first subscriber.
  void startPolling() {
    _listenerCount++;
    if (_pollingTimer != null) return;
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      final level = getActiveAudioLevel();
      if ((level - levelNotifier.value).abs() > 0.005) {
        levelNotifier.value = level;
      }
    });
  }

  /// Stops the shared polling timer when the last consumer unsubscribes.
  void stopPolling() {
    _listenerCount = (_listenerCount - 1).clamp(0, 999);
    if (_listenerCount == 0) {
      _pollingTimer?.cancel();
      _pollingTimer = null;
      levelNotifier.value = 0.0;
    }
  }
}
