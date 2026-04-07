import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lynk_x/presentation/features/wallet/models/wallet_model.dart';
import 'wallet_state.dart';

/// WalletCubit — owns wallet balance, transaction history, and top-up flow.
///
/// Architecture notes:
/// - Fetches the user's account_wallets and paginated transactions from Supabase.
/// - Subscribes to a Realtime channel on account_wallets so the balance tile
///   updates instantly after a payment webhook is processed (no pull-to-refresh).
/// - Top-up initiates an RPC call that returns a payment gateway URL; the app
///   opens it in an in-app browser / WebView and polls the status on resume.
/// - Page size is 20 (matches delivery_queue batch size for consistency).
class WalletCubit extends Cubit<WalletState> {
  WalletCubit() : super(const WalletState());

  final _supabase = Supabase.instance.client;

  // Realtime subscription for live balance updates
  RealtimeChannel? _balanceChannel;

  // Pagination
  static const int _pageSize = 20;
  int _currentPage = 0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Fetch initial wallet data and subscribe to realtime balance updates.
  Future<void> init() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    await Future.wait([_fetchBalances(), _fetchTransactions(reset: true)]);
    _subscribeToBalanceUpdates();
  }

  @override
  Future<void> close() {
    _balanceChannel?.unsubscribe();
    return super.close();
  }

  // ── Data Fetching ──────────────────────────────────────────────────────────

  Future<void> _fetchBalances() async {
    try {
      // Fetch all wallets for the current user's account(s)
      final response = await _supabase
          .from('account_wallets')
          .select('currency, balance, pending_balance')
          .order('currency', ascending: true);

      final balances = (response as List)
          .map((row) => WalletBalance.fromMap(row as Map<String, dynamic>))
          .toList();

      emit(state.copyWith(balances: balances, isLoading: false));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to load wallet balances: ${e.toString()}',
      ));
    }
  }

  Future<void> _fetchTransactions({bool reset = false}) async {
    if (reset) _currentPage = 0;

    emit(state.copyWith(
      isLoadingMore: !reset,
      isLoading:     reset,
    ));

    try {
      final from = _currentPage * _pageSize;
      final to   = from + _pageSize - 1;

      final response = await _supabase
          .from('transactions')
          .select('id, category, reason, amount, currency, status, created_at, metadata')
          .order('created_at', ascending: false)
          .range(from, to);

      final rows = (response as List)
          .map((row) => WalletTransaction.fromMap(row as Map<String, dynamic>))
          .toList();

      final updated = reset ? rows : [...state.transactions, ...rows];

      emit(state.copyWith(
        transactions:  updated,
        hasMore:       rows.length == _pageSize,
        isLoadingMore: false,
        isLoading:     false,
      ));

      if (rows.isNotEmpty) _currentPage++;
    } catch (e) {
      emit(state.copyWith(
        isLoading:     false,
        isLoadingMore: false,
        error: 'Failed to load transactions: ${e.toString()}',
      ));
    }
  }

  /// Pull-to-refresh — resets and refetches everything.
  Future<void> refresh() async {
    await Future.wait([_fetchBalances(), _fetchTransactions(reset: true)]);
  }

  /// Load the next page of transactions (infinite scroll).
  Future<void> loadMoreTransactions() async {
    if (state.isLoadingMore || !state.hasMore) return;
    await _fetchTransactions(reset: false);
  }

  // ── Realtime ───────────────────────────────────────────────────────────────

  /// Subscribe to INSERT/UPDATE events on account_wallets for live balance.
  /// When the payment webhook Edge Function credits the wallet, the UI tile
  /// updates without requiring a manual refresh.
  void _subscribeToBalanceUpdates() {
    _balanceChannel = _supabase
        .channel('wallet_balance_updates')
        .onPostgresChanges(
          event:  PostgresChangeEvent.all,
          schema: 'public',
          table:  'account_wallets',
          callback: (_) => _fetchBalances(),
        )
        .subscribe();
  }

  // ── Top-up Flow ────────────────────────────────────────────────────────────

  /// Initiate a wallet top-up via the platform payment gateway.
  ///
  /// [amount]   - The amount in the user's local currency.
  /// [currency] - ISO 4217 currency code (e.g., 'KES', 'NGN', 'USD').
  ///
  /// On success, emits [TopUpStatus.success] and a [topUpPaymentUrl] that
  /// the calling screen should open in a WebView / in-app browser.
  Future<void> initiateTopUp({
    required double amount,
    required String currency,
  }) async {
    if (amount <= 0) {
      emit(state.copyWith(
        topUpStatus: TopUpStatus.error,
        topUpError:  'Top-up amount must be greater than zero.',
      ));
      return;
    }

    emit(state.copyWith(topUpStatus: TopUpStatus.submitting, clearTopUpError: true));

    try {
      final response = await _supabase.rpc('initiate_wallet_topup', params: {
        'p_amount':   amount,
        'p_currency': currency,
      });

      final paymentUrl = response['payment_url'] as String?;

      if (paymentUrl == null || paymentUrl.isEmpty) {
        emit(state.copyWith(
          topUpStatus: TopUpStatus.error,
          topUpError:  'Payment gateway did not return a redirect URL.',
        ));
        return;
      }

      emit(state.copyWith(
        topUpStatus:     TopUpStatus.success,
        topUpPaymentUrl: paymentUrl,
      ));
    } catch (e) {
      emit(state.copyWith(
        topUpStatus: TopUpStatus.error,
        topUpError:  'Top-up failed: ${e.toString()}',
      ));
    }
  }

  /// Reset top-up state (called after the WebView closes, successful or not).
  void resetTopUp() {
    emit(state.copyWith(
      topUpStatus:    TopUpStatus.idle,
      clearTopUpError: true,
      clearPaymentUrl: true,
    ));
    // Re-fetch balance in case the payment succeeded
    _fetchBalances();
  }
}
