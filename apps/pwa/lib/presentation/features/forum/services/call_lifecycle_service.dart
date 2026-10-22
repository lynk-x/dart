import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:lynk_x/presentation/features/forum/services/call_sound_service.dart';
import 'package:lynk_x/presentation/features/forum/services/mic_status_reporter.dart';
import 'package:lynk_x/presentation/features/forum/services/audio_telemetry_service.dart';

/// Coordinates the side effects that must fire exactly once per call
/// lifecycle transition (join/leave) across the audio, video, sound, mic
/// reporting, and telemetry services.
///
/// Without this, each service fires independently on join/leave and can
/// race: the join chime can fire twice (once from the audio cubit, once from
/// the video service), telemetry can keep polling after teardown, and
/// `reportMicStatus` can run before the mic is actually up. This service
/// serialises the transition so each step runs in order and exactly once.
///
/// ## Coverage
///
/// Audio-call lifecycle: the audio cubit calls [join]/[leave] from its
/// broadcast-event handlers and start/end methods.
///
/// Video-call lifecycle: [ForumVideoStage] calls [join] after the camera and
/// microphone are up (in `_initCameraAndAudio`), and [leave] on end-stream
/// and dispose. Video's lifecycle is widget-mount-driven rather than
/// broadcast-driven, but the side effects — chime, mic reporting, telemetry
/// start/stop — are identical, so it routes through the same service.
class CallLifecycleService {
  static final CallLifecycleService _instance = CallLifecycleService._internal();
  factory CallLifecycleService() => _instance;
  CallLifecycleService._internal();

  bool _joined = false;
  bool _joinInProgress = false;
  final List<Future<void> Function()> _onJoinHooks = [];
  final List<void Function()> _onLeaveHooks = [];

  /// Registers an async side effect to run after a successful join. Idempotent
  /// per hook identity so re-registration can't double-fire.
  void onJoin(Future<void> Function() hook) {
    if (_onJoinHooks.contains(hook)) return;
    _onJoinHooks.add(hook);
  }

  /// Registers a side effect to run on leave.
  void onLeave(void Function() hook) {
    if (_onLeaveHooks.contains(hook)) return;
    _onLeaveHooks.add(hook);
  }

  /// Runs the join sequence exactly once. Subsequent calls before [leave]
  /// are no-ops — prevents double-firing when both the audio cubit and the
  /// video service trigger a join.
  Future<void> join() async {
    if (_joined || _joinInProgress) return;
    _joinInProgress = true;
    try {
      // Sound first — the chime is the first thing a listener hears.
      await CallSoundService.playJoin();
      // Mic reporting runs after the mic is up; it never throws.
      reportMicStatus();
      // Telemetry starts polling once the session is live.
      AudioTelemetryService().startPolling();
      for (final hook in _onJoinHooks) {
        try {
          await hook();
        } catch (e, stack) {
          debugPrint('[CallLifecycleService] join hook failed: $e\n$stack');
        }
      }
      _joined = true;
    } finally {
      _joinInProgress = false;
    }
  }

  /// Runs the leave sequence exactly once and resets join state so a
  /// subsequent [join] can fire again.
  void leave() {
    if (!_joined) return;
    AudioTelemetryService().stopPolling();
    for (final hook in _onLeaveHooks) {
      try {
        hook();
      } catch (e, stack) {
        debugPrint('[CallLifecycleService] leave hook failed: $e\n$stack');
      }
    }
    _joined = false;
    _joinInProgress = false;
  }

  bool get isJoined => _joined;
}