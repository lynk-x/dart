import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/data/repositories/repositories.dart';

/// Owns the realtime subscription to `finance.account_wallets` for a given
/// account, plus exponential-backoff reconnect on channel error/timeout.
///
/// Extracted from WalletCubit so the reconnect state machine (timer, delay,
/// backoff cap) is testable/readable in isolation from balance-fetching and
/// PIN/security concerns.
class BalanceRealtimeSubscriber {
  BalanceRealtimeSubscriber(this._repo);

  final WalletRepository _repo;

  RealtimeChannel? _channel;
  Timer? _reconnectTimer;
  Duration _reconnectDelay = const Duration(seconds: 2);

  /// Subscribes to balance changes for [accountId]. [onUpdate] fires on every
  /// INSERT/UPDATE. [onStatus] fires on subscribe/error/timeout so the caller
  /// can surface connectivity state to the UI.
  void subscribe({
    required String accountId,
    required void Function(PostgresChangePayload) onUpdate,
    required void Function(RealtimeSubscribeStatus status) onStatus,
  }) {
    _channel = _repo.subscribeToBalance(accountId, onUpdate).subscribe((status, [error]) {
      onStatus(status);
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        _scheduleReconnect(accountId: accountId, onUpdate: onUpdate, onStatus: onStatus);
      } else if (status == RealtimeSubscribeStatus.subscribed) {
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _reconnectDelay = const Duration(seconds: 2);
      }
    });
  }

  void _scheduleReconnect({
    required String accountId,
    required void Function(PostgresChangePayload) onUpdate,
    required void Function(RealtimeSubscribeStatus status) onStatus,
  }) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnectDelay = _reconnectDelay * 2;
      if (_reconnectDelay > const Duration(seconds: 30)) {
        _reconnectDelay = const Duration(seconds: 30);
      }
      unsubscribe();
      subscribe(accountId: accountId, onUpdate: onUpdate, onStatus: onStatus);
    });
  }

  /// Resets backoff and reconnects immediately — call when connectivity is
  /// restored so the app doesn't wait out a stale backoff delay.
  void reconnectNow({
    required String accountId,
    required void Function(PostgresChangePayload) onUpdate,
    required void Function(RealtimeSubscribeStatus status) onStatus,
  }) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectDelay = const Duration(seconds: 2);
    unsubscribe();
    subscribe(accountId: accountId, onUpdate: onUpdate, onStatus: onStatus);
  }

  void unsubscribe() {
    _channel?.unsubscribe();
    _channel = null;
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unsubscribe();
  }
}
