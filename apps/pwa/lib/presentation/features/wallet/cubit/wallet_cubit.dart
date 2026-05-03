import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynk_x/data/repositories/repositories.dart';
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
  final WalletRepository _repo;
  WalletCubit(this._repo) : super(const WalletState());

  final _supabase = Supabase.instance.client;
  final _localAuth = LocalAuthentication();

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
    await Future.wait([
      _fetchBalances(),
      _fetchTransactions(reset: true),
      _checkPinStatus(),
      _loadBiometricPreference(),
      _loadPrivacyPreference(),
    ]);
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
      final accountId = state.accountId ?? await _resolveAccountId();
      if (accountId == null) {
        emit(state.copyWith(isLoading: false));
        return;
      }

      final currencies = ['KES', 'USD'];
      final responses = await Future.wait(
        currencies.map((c) => _repo.getWalletBalance(accountId, c)),
      );

      final balances = responses
          .whereType<Map<String, dynamic>>()
          .map((row) => WalletBalance.fromMap({
                ...row,
                'pending_balance': row['escrow_balance'],
              }))
          .toList();

      emit(state.copyWith(balances: balances, accountId: accountId, isLoading: false));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to load wallet balances: ${e.toString()}',
      ));
    }
  }

  Future<String?> _resolveAccountId() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _supabase
        .from('account_members')
        .select('account_id')
        .eq('user_id', userId)
        .eq('role_slug', 'owner')
        .order('created_at', ascending: true)
        .limit(1)
        .maybeSingle();
    return row?['account_id'] as String?;
  }

  Future<void> _fetchTransactions({bool reset = false}) async {
    if (reset) _currentPage = 0;

    emit(state.copyWith(
      isLoadingMore: !reset,
      isLoading:     reset,
    ));

    try {
      final accountId = state.accountId;
      if (accountId == null) {
        emit(state.copyWith(isLoading: false, isLoadingMore: false));
        return;
      }

      final from = _currentPage * _pageSize;
      final rows = await _repo.getTimeline(
        accountId,
        limit: _pageSize,
        offset: from,
        currency: state.selectedCurrency,
      );

      final typed = rows
          .map((row) => WalletTransaction.fromMap(row))
          .toList();

      final updated = reset ? typed : [...state.transactions, ...typed];

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
  ///
  /// Filters by the user's account_id so the channel only emits relevant rows
  /// (RLS already enforces this server-side, but client-side filtering avoids
  /// waking the cubit on every other user's wallet update). On RLS denial,
  /// the subscribe callback receives `RealtimeSubscribeStatus.channelError` —
  /// surface it through state so the UI can show a stale-data hint.
  void _subscribeToBalanceUpdates() {
    final accountId = state.accountId;
    if (accountId == null) return; // No account loaded yet — caller will retry.

    _balanceChannel = _repo.subscribeToBalance(accountId, (_) => _fetchBalances())
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            // Surface to state — most commonly an RLS denial or network blip.
            // Keeps the UI honest about whether realtime is live.
            emit(state.copyWith(
              error: 'Realtime balance updates unavailable. Pull to refresh.',
            ));
          }
        });
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
    required String pin,
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
      final hash = _hashPin(pin);
      await _supabase.rpc('request_attendee_withdrawal', params: {
        'p_amount':            amount,
        'p_currency':          currency,
        'p_payout_method_id':  payoutMethodId,
        'p_pin_hash':          hash,
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

  /// Transfer funds to another account.
  Future<void> transferFunds({
    required double amount,
    required String currency,
    required String recipientAccountId,
    required String pin,
  }) async {
    if (amount <= 0) {
      emit(state.copyWith(
        withdrawStatus: WithdrawStatus.error,
        withdrawError:  'Transfer amount must be greater than zero.',
      ));
      return;
    }

    emit(state.copyWith(
      withdrawStatus: WithdrawStatus.submitting,
      clearWithdrawError: true,
    ));

    try {
      final hash = _hashPin(pin);
      await _supabase.rpc('transfer_funds', params: {
        'p_amount':               amount,
        'p_currency':             currency,
        'p_recipient_account_id': recipientAccountId,
        'p_pin_hash':             hash,
      });

      emit(state.copyWith(withdrawStatus: WithdrawStatus.success));
      await _fetchBalances(); // Reflect the debit immediately
    } catch (e) {
      emit(state.copyWith(
        withdrawStatus: WithdrawStatus.error,
        withdrawError:  'Transfer failed: ${e.toString()}',
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

  void setCurrency(String? currency) {
    if (state.selectedCurrency == currency) return;
    emit(state.copyWith(
      selectedCurrency: currency,
      clearSelectedCurrency: currency == null,
    ));
    _fetchTransactions(reset: true);
  }

  /// Explicitly create a zero-balance wallet for a currency.
  Future<void> createWallet(String currency) async {
    try {
      emit(state.copyWith(isLoading: true));
      await _supabase.rpc('create_wallet', params: {'p_currency': currency});
      await _fetchBalances();
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to create wallet: ${e.toString()}',
      ));
    }
  }

  // ── Security ───────────────────────────────────────────────────────────────

  Future<void> _checkPinStatus() async {
    try {
      final res = await _supabase
          .from('user_profile')
          .select('wallet_pin_hash')
          .eq('id', _supabase.auth.currentUser?.id ?? '')
          .single();

      final hasPin = res['wallet_pin_hash'] != null;
      emit(state.copyWith(hasPinSet: hasPin));
    } catch (_) {}
  }

  String _hashPin(String pin) {
    final salt = _supabase.auth.currentUser?.id ?? 'lynk-salt';
    final bytes = utf8.encode(pin + salt);
    return sha256.convert(bytes).toString();
  }

  Future<void> setWalletPin(String pin) async {
    try {
      emit(state.copyWith(isLoading: true));
      final hash = _hashPin(pin);
      await _supabase.rpc('set_wallet_pin', params: {'p_pin_hash': hash});
      emit(state.copyWith(hasPinSet: true, isWalletUnlocked: true, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: 'Failed to set PIN: ${e.toString()}'));
    }
  }

  Future<bool> unlockWithPin(String pin) async {
    try {
      final hash = _hashPin(pin);
      final isValid = await _supabase.rpc('verify_wallet_pin', params: {'p_pin_hash': hash}) as bool;
      if (isValid) {
        emit(state.copyWith(isWalletUnlocked: true));
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;

      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Unlock your Lynk-X Wallet',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );

      if (didAuth) {
        emit(state.copyWith(isWalletUnlocked: true));
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void lockWallet() {
    emit(state.copyWith(isWalletUnlocked: false));
  }

  Future<void> _loadBiometricPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final useBio = prefs.getBool('wallet_use_biometrics_v1') ?? false;
    emit(state.copyWith(useBiometrics: useBio));
  }

  Future<void> toggleBiometrics(bool enable) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wallet_use_biometrics_v1', enable);
    emit(state.copyWith(useBiometrics: enable));
  }

  /// PIN Recovery Strategy:
  /// Since the Wallet PIN is a second factor of authentication, recovery must
  /// be tied to the primary account security.
  ///
  /// 1. A "Forgot PIN" action will trigger a server-side event that sends a
  ///    secure one-time-link (OTL) to the user's registered email/phone.
  /// 2. Clicking the OTL will allow the user to set a new PIN.
  /// 3. As a safety measure, resetting the PIN will place a 24-48 hour "hold"
  ///    on high-value withdrawals to prevent account takeover abuse.

   Future<void> _loadPrivacyPreference() async {
     final prefs = await SharedPreferences.getInstance();
     final enabled = prefs.getBool('wallet_privacy_mode_v1') ?? false;
     emit(state.copyWith(isPrivacyModeEnabled: enabled));
   }

   Future<void> togglePrivacyMode(bool enable) async {
     final prefs = await SharedPreferences.getInstance();
     await prefs.setBool('wallet_privacy_mode_v1', enable);
     emit(state.copyWith(isPrivacyModeEnabled: enable));
   }
}
