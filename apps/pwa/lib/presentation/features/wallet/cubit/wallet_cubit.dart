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

  // Auth state subscription — re-subscribes balance channel on session recovery
  StreamSubscription<AuthState>? _authSubscription;

  // Pagination
  static const int _pageSize = 20;
  int _currentPage = 0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Fetch initial wallet data and subscribe to realtime balance updates.
  Future<void> init() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    await Future.wait([_fetchBalances(), _fetchTransactions(reset: true)]);
    _subscribeToBalanceUpdates();
    _authSubscription = _supabase.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.tokenRefreshed ||
          event.event == AuthChangeEvent.signedIn) {
        _balanceChannel?.unsubscribe();
        _subscribeToBalanceUpdates();
        _fetchBalances();
      }
    });
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
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
          // Explicit user_id filter for defense-in-depth — RLS is not a substitute
          // for a missing WHERE clause when the column is available.
          .eq('user_id', _supabase.auth.currentUser?.id ?? '')
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

  /// Initiate an M-Pesa STK push top-up.
  ///
  /// Calls the `initiate-mpesa-topup` Edge Function, which sends an STK push
  /// to [phone]. The wallet balance update arrives asynchronously via the
  /// M-Pesa webhook → the Realtime subscription detects the increase.
  Future<void> initiateTopUpMpesa({
    required double amount,
    required String currency,
    required String phone,
  }) async {
    if (amount <= 0) {
      emit(state.copyWith(
        topUpStatus: TopUpStatus.error,
        topUpError:  'Amount must be greater than zero.',
      ));
      return;
    }

    emit(state.copyWith(topUpStatus: TopUpStatus.submitting, clearTopUpError: true));

    try {
      await _supabase.functions.invoke(
        'initiate-mpesa-topup',
        body: {'amount': amount, 'currency': currency, 'phone': phone},
      );
      // Transition to waiting — Realtime will detect the balance change.
      emit(state.copyWith(topUpStatus: TopUpStatus.waitingMpesa));
    } catch (e) {
      emit(state.copyWith(
        topUpStatus: TopUpStatus.error,
        topUpError:  'M-Pesa request failed: ${e.toString()}',
      ));
    }
  }

  /// Initiate a card top-up via an external gateway (Stripe / Flutterwave).
  /// Returns a redirect URL that the calling screen opens in a browser.
  Future<void> initiateTopUpCard({
    required double amount,
    required String currency,
  }) async {
    if (amount <= 0) {
      emit(state.copyWith(
        topUpStatus: TopUpStatus.error,
        topUpError:  'Amount must be greater than zero.',
      ));
      return;
    }

    emit(state.copyWith(topUpStatus: TopUpStatus.submitting, clearTopUpError: true));

    try {
      final response = await _supabase.functions.invoke(
        'initiate-card-topup',
        body: {'amount': amount, 'currency': currency},
      );

      final paymentUrl = (response.data as Map<String, dynamic>?)?['payment_url'] as String?;
      if (paymentUrl == null || paymentUrl.isEmpty) {
        emit(state.copyWith(
          topUpStatus: TopUpStatus.error,
          topUpError:  'Payment gateway did not return a redirect URL.',
        ));
        return;
      }

      emit(state.copyWith(topUpStatus: TopUpStatus.success, topUpPaymentUrl: paymentUrl));
    } catch (e) {
      emit(state.copyWith(
        topUpStatus: TopUpStatus.error,
        topUpError:  'Top-up failed: ${e.toString()}',
      ));
    }
  }

  /// Reset top-up state — called when the sheet closes or the user cancels.
  void resetTopUp() {
    emit(state.copyWith(
      topUpStatus:     TopUpStatus.idle,
      clearTopUpError: true,
      clearPaymentUrl: true,
    ));
    _fetchBalances();
  }

  // ── Withdrawal Flow ───────────────────────────────────────────────────────

  /// Fetch payout methods, KYC tier, and account_id for the current user.
  Future<void> loadPayoutMethods() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Resolve personal account (oldest owner membership = personal account)
      final memberData = await _supabase
          .from('account_members')
          .select('account_id')
          .eq('user_id', userId)
          .eq('role_slug', 'owner')
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle();

      if (memberData == null) return;

      final accountId = memberData['account_id'] as String;

      // Fetch methods + provider metadata in one query via FK traversal
      final methodRows = await _supabase
          .from('account_payment_methods')
          .select('id, provider_identity, metadata, platform_payment_providers(provider_name, display_name)')
          .eq('account_id', accountId);

      // Fetch latest KYC verification for this account
      final kycRow = await _supabase
          .from('identity_verifications')
          .select('kyc_tier, status')
          .eq('account_id', accountId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final kycTier = (kycRow != null && kycRow['status'] == 'approved')
          ? kycRow['kyc_tier'] as String?
          : null;

      emit(state.copyWith(
        payoutMethods: List<Map<String, dynamic>>.from(methodRows),
        kycTier:       kycTier,
        accountId:     accountId,
      ));
    } catch (_) {}
  }

  /// Register a new payout method (e.g. M-Pesa phone) via RPC.
  Future<void> addPayoutMethod({
    required String providerName,
    required String identity,
    required String label,
  }) async {
    emit(state.copyWith(
      withdrawStatus: WithdrawStatus.addingMethod,
      clearWithdrawError: true,
    ));
    try {
      await _supabase.rpc('add_payout_method', params: {
        'p_provider_name': providerName,
        'p_identity':      identity,
        'p_label':         label,
      });
      emit(state.copyWith(withdrawStatus: WithdrawStatus.idle));
      await loadPayoutMethods(); // Refresh list so new method appears
    } catch (e) {
      emit(state.copyWith(
        withdrawStatus: WithdrawStatus.error,
        withdrawError:  'Could not add payout method: ${e.toString()}',
      ));
    }
  }

  /// Request a withdrawal to a registered payout method.
  /// Uses request_attendee_withdrawal RPC (no business_profile requirement).
  Future<void> requestWithdrawal({
    required double amount,
    required String currency,
    required String payoutMethodId,
  }) async {
    if (amount <= 0) {
      emit(state.copyWith(
        withdrawStatus: WithdrawStatus.error,
        withdrawError:  'Withdrawal amount must be greater than zero.',
      ));
      return;
    }

    emit(state.copyWith(
      withdrawStatus: WithdrawStatus.submitting,
      clearWithdrawError: true,
    ));

    try {
      await _supabase.rpc('request_attendee_withdrawal', params: {
        'p_amount':            amount,
        'p_currency':          currency,
        'p_payout_method_id':  payoutMethodId,
      });

      emit(state.copyWith(withdrawStatus: WithdrawStatus.success));
      await _fetchBalances(); // Reflect the escrow hold immediately
    } catch (e) {
      emit(state.copyWith(
        withdrawStatus: WithdrawStatus.error,
        withdrawError:  'Withdrawal failed: ${e.toString()}',
      ));
    }
  }

  /// Reset withdrawal state after dialog closes.
  void resetWithdraw() {
    emit(state.copyWith(
      withdrawStatus:     WithdrawStatus.idle,
      clearWithdrawError: true,
    ));
  }

  void reset() {
    _balanceChannel?.unsubscribe();
    _balanceChannel = null;
    emit(const WalletState());
  }
}
