import 'dart:async';

/// A reusable debouncer — delays [action] until [duration] elapses with no
/// new call. Repeated calls reset the timer.
///
/// `base_message_cubit` reinvented this inline (`searchTimer = Timer(const
/// Duration(milliseconds: 300), …)`); `wallet_cubit` and `forum_media_cubit`
/// would use the same primitive. Cancelling on close is the caller's job —
/// call [cancel] in the cubit's `close()`.
class Debouncer {
  Debouncer(this.duration);

  final Duration duration;
  Timer? _timer;

  /// Schedules [action]. Any pending call is cancelled first.
  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// Cancels any pending call without running it.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  bool get isScheduled => _timer != null;
}