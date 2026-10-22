import 'dart:async';
import 'package:flutter/foundation.dart';

/// Centralizes reconnect/retry policy across audio and video calls.
///
/// `ForumVideoStreamService` already tracks `isReconnectingNotifier` for both
/// the publish side and the listener side, but each side has its own retry
/// count, backoff, and give-up threshold — and audio calls have none at all.
/// This service owns one policy so a dropped audio call and a dropped video
/// stream use the same recovery shape.
///
/// Callers register a [RecoveryAction] per side; the service runs them on
/// [requestReconnect] and stops after [maxAttempts] exhausted attempts, at
/// which point [onGiveUp] fires.
///
/// ## Lifecycle contract
///
/// `requestReconnect` is a fire-and-forget loop that keeps retrying through
/// backoff delays even after the caller is gone — it doesn't know about
/// widget lifecycle. The caller MUST call [cancel] from its `dispose()`
/// (or `close()`) to stop the loop and reset attempt state. Both the audio
/// cubit and the video stage do this; any new caller must too. Without it,
/// a disposed widget's recovery keeps burning attempts and network calls
/// until the give-up threshold, and `onGiveUp` fires against a dead context.
class CallRecoveryService {
  static final CallRecoveryService _instance = CallRecoveryService._internal();
  factory CallRecoveryService() => _instance;
  CallRecoveryService._internal();

  static const int _kMaxAttempts = 3;
  static const Duration _kBaseBackoff = Duration(seconds: 1);

  final ValueNotifier<bool> isRecoveringNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> attemptNotifier = ValueNotifier<int>(0);

  RecoveryAction? _publishAction;
  RecoveryAction? _listenerAction;
  Timer? _backoffTimer;
  int _attempts = 0;
  bool _recovering = false;

  /// Registers the recovery action for the publish side (host/co-host).
  void setPublishAction(RecoveryAction action) => _publishAction = action;

  /// Registers the recovery action for the listener side (pure listener/co-host receive).
  void setListenerAction(RecoveryAction action) => _listenerAction = action;

  /// Requests a reconnect for the given side. Runs the registered action
  /// immediately; if it throws, backs off exponentially and retries up to
  /// [maxAttempts], then fires [onGiveUp].
  ///
  /// A [RecoveryAbort] thrown by the action is treated as a hard stop —
  /// the caller is gone (cubit closed, widget disposed) and retrying would
  /// only waste attempts. Regular exceptions are retryable.
  Future<void> requestReconnect({
    required RecoverySide side,
    required VoidCallback onGiveUp,
  }) async {
    final action = side == RecoverySide.publish ? _publishAction : _listenerAction;
    if (action == null) return;
    if (_recovering) return;
    _recovering = true;
    isRecoveringNotifier.value = true;

    try {
      while (_attempts < _kMaxAttempts) {
        _attempts++;
        attemptNotifier.value = _attempts;
        try {
          await action.run();
          // Success — reset and stop.
          _attempts = 0;
          isRecoveringNotifier.value = false;
          _recovering = false;
          return;
        } on RecoveryAbort catch (_) {
          // Hard stop — caller is gone, don't retry.
          _attempts = 0;
          isRecoveringNotifier.value = false;
          _recovering = false;
          return;
        } catch (e) {
          debugPrint(
            '[CallRecoveryService] ${side.name} reconnect attempt $_attempts failed: $e',
          );
          if (_attempts >= _kMaxAttempts) break;
          final backoff = Duration(
            milliseconds: (_kBaseBackoff.inMilliseconds * (1 << (_attempts - 1))).clamp(
              _kBaseBackoff.inMilliseconds,
              30000,
            ),
          );
          _backoffTimer = Timer(backoff, () {});
          await Future.delayed(backoff);
        }
      }
      // Exhausted.
      _attempts = 0;
      isRecoveringNotifier.value = false;
      _recovering = false;
      onGiveUp();
    } finally {
      _backoffTimer?.cancel();
      _backoffTimer = null;
    }
  }

  /// Cancels any in-flight recovery and resets attempt state.
  void cancel() {
    _backoffTimer?.cancel();
    _backoffTimer = null;
    _attempts = 0;
    _recovering = false;
    isRecoveringNotifier.value = false;
    attemptNotifier.value = 0;
  }
}

enum RecoverySide { publish, listener }

/// A single reconnect attempt for one side of a call.
class RecoveryAction {
  final Future<void> Function() run;

  const RecoveryAction(this.run);
}

/// Thrown by a [RecoveryAction] to signal that recovery should stop
/// immediately — the caller is gone (cubit closed, widget disposed) and
/// retrying would only waste attempts. Distinct from a regular exception,
/// which the service treats as retryable.
class RecoveryAbort implements Exception {
  final String reason;
  RecoveryAbort(this.reason);

  @override
  String toString() => 'RecoveryAbort: $reason';
}