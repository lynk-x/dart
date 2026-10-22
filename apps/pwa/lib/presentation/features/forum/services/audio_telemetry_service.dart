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
///
/// The polling timer also stops automatically when no session is live,
/// so a cubit that forgets to call [stopPolling] on teardown can't leave
/// a timer running forever. Callers that flip live state should call
/// [setLive] to keep the timer in step.
class AudioTelemetryService {
  static final AudioTelemetryService _instance = AudioTelemetryService._internal();
  factory AudioTelemetryService() => _instance;
  AudioTelemetryService._internal();

  /// Shared audio level notifier (0.0–1.0) driven by the singleton polling timer.
  /// Widgets should listen to this rather than calling [getActiveAudioLevel] on their own timers.
  final ValueNotifier<double> levelNotifier = ValueNotifier(0.0);

  /// Whether an active call/stream is live. The polling timer stops when this
  /// is false, so a session ending without an explicit [stopPolling] can't
  /// leave the timer running.
  final ValueNotifier<bool> isLiveNotifier = ValueNotifier<bool>(false);

  Timer? _pollingTimer;
  int _listenerCount = 0;

  final ForumAudioStreamService _audioService = ForumAudioStreamService();

  /// Updates [isLiveNotifier]. Call from the audio cubit and the video
  /// service whenever live state changes.
  void setLive(bool live) {
    if (isLiveNotifier.value == live) return;
    isLiveNotifier.value = live;
    if (!live && _pollingTimer != null && _listenerCount > 0) {
      // Session ended while consumers were still registered — stop polling
      // rather than burning ticks on a dead session.
      _pollingTimer?.cancel();
      _pollingTimer = null;
      levelNotifier.value = 0.0;
    }
  }

  /// Gets the current audio level synchronously (0.0–1.0) for the active session.
  double getActiveAudioLevel() {
    if (ForumVideoStreamService().isLiveNotifier.value) {
      final level = ForumVideoStreamService().getAudioLevel();
      if (level > 0.0) return level;
    }
    final audioStreamLevel = _audioService.getAudioLevel();
    if (audioStreamLevel > 0.0) return audioStreamLevel;
    return 0.0;
  }

  /// Starts the shared polling timer. Call once per consumer that needs the notifier.
  /// The timer is ref-counted and starts only on the first subscriber.
  void startPolling() {
    _listenerCount++;
    if (_pollingTimer != null) return;
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      // Auto-stop if the session ended without an explicit stopPolling.
      if (!isLiveNotifier.value) {
        stopPolling();
        return;
      }
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