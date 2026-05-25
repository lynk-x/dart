import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/web_authn_helper.dart';
import '../utils/connectivity_helper.dart';

import 'package:lynk_x/data/repositories/repositories.dart';
import 'package:lynk_x/presentation/features/wallet/models/wallet_model.dart';
import 'package:lynk_core/core.dart';
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
  
  // Connectivity subscription — instantly restores realtime connection when returning online
  StreamSubscription<bool>? _connectivitySubscription;

  // Pagination
  static const int _pageSize = 20;
  int _currentPage = 0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Fetch initial wallet data and subscribe to realtime balance updates.
  Future<void> init() async {
    await _authSubscription?.cancel();
    _balanceChannel?.unsubscribe();

    emit(state.copyWith(isLoading: true, clearError: true));
    await _loadCachedData();

    // Resolve Account ID first to ensure downstream concurrent methods are initialized correctly
    final accountId = state.accountId ?? await _resolveAccountId();
    if (accountId != null) {
      emit(state.copyWith(accountId: accountId));
    }

    await Future.wait([
      _fetchBalances(),
      _fetchTransactions(reset: true),
      _checkPinStatus(),
      _loadBiometricPreference(),
      _loadPrivacyPreference(),
    ]);
    _subscribeToBalanceUpdates();

    await _connectivitySubscription?.cancel();
    _connectivitySubscription = ConnectivityHelper.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _reconnectDelay = const Duration(seconds: 2);
        
        _balanceChannel?.unsubscribe();
        _subscribeToBalanceUpdates();
      }
    });
    _authSubscription = _supabase.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.tokenRefreshed ||
          event.event == AuthChangeEvent.signedIn) {
        _balanceChannel?.unsubscribe();
        _subscribeToBalanceUpdates();
        _fetchBalances();
      }
    });
  }

  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final balancesStr = prefs.getString('cached_balances');
      if (balancesStr != null) {
        final decoded = jsonDecode(balancesStr) as List;
        final balances = decoded.map((e) => WalletBalance.fromMap(Map<String, dynamic>.from(e))).toList();
        emit(state.copyWith(balances: balances));
      }

      final txStr = prefs.getString('cached_transactions');
      if (txStr != null) {
        final decoded = jsonDecode(txStr) as List;
        final txs = decoded.map((e) => WalletTransaction.fromMap(Map<String, dynamic>.from(e))).toList();
        emit(state.copyWith(transactions: txs));
      }
    } catch (_) {}
  }

  Future<void> _saveCachedBalances(List<WalletBalance> balances) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(balances.map((b) => {
        'currency': b.currency,
        'cash_balance': b.cashBalance,
        'escrow_balance': b.pendingBalance,
        'credit_balance': b.creditBalance,
      }).toList());
      await prefs.setString('cached_balances', encoded);
    } catch (_) {}
  }

  Future<void> _saveCachedTransactions(List<WalletTransaction> txs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final topTxs = txs.take(20).toList(); // Only cache latest 20
      final encoded = jsonEncode(topTxs.map((t) => {
        'id': t.id,
        'entry_type': t.entryType,
        'category': t.category,
        'reason': t.reason,
        'amount': t.amount,
        'currency': t.currency,
        'status': t.status,
        'event_id': t.eventId,
        'reference': t.reference,
        'created_at': t.createdAt.toIso8601String(),
      }).toList());
      await prefs.setString('cached_transactions', encoded);
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _balanceChannel?.unsubscribe();
    _reconnectTimer?.cancel();
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
                'escrow_balance': row['escrow_balance'], // Fix to properly use escrow_balance in fromMap
              }))
          .toList();

      emit(state.copyWith(balances: balances, accountId: accountId, isLoading: false));
      _saveCachedBalances(balances);
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to load wallet balances: ${e.toFriendlyMessage()}',
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

      if (reset) {
        _saveCachedTransactions(updated);
      }

      if (rows.isNotEmpty) _currentPage++;
    } catch (e) {
      emit(state.copyWith(
        isLoading:     false,
        isLoadingMore: false,
        error: 'Failed to load transactions: ${e.toFriendlyMessage()}',
      ));
    }
  }

  /// Pull-to-refresh — resets and refetches everything.
  Future<void> refresh() async {
    final accountId = state.accountId ?? await _resolveAccountId();
    if (accountId != null) {
      emit(state.copyWith(accountId: accountId));
    }
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
  Timer? _reconnectTimer;
  Duration _reconnectDelay = const Duration(seconds: 2);

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
              error: 'Realtime balance updates unavailable. Reconnecting...',
            ));
            _scheduleBalanceReconnect();
          } else if (status == RealtimeSubscribeStatus.subscribed) {
            emit(state.copyWith(clearError: true));
            _reconnectTimer?.cancel();
            _reconnectTimer = null;
            _reconnectDelay = const Duration(seconds: 2);
          }
        });
  }

  void _scheduleBalanceReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnectDelay = _reconnectDelay * 2;
      if (_reconnectDelay > const Duration(seconds: 30)) {
        _reconnectDelay = const Duration(seconds: 30);
      }
      _balanceChannel?.unsubscribe();
      _subscribeToBalanceUpdates();
    });
  }

  // ── Top-up Flow ────────────────────────────────────────────────────────────

  /// Initiate a wallet top-up using any supported provider.
  /// Calls the `initiate_wallet_topup` RPC. If the backend returns a payment_url,
  /// it will be surfaced to the UI to open in a browser. For M-Pesa STK push,
  /// the URL might be null if the STK push was dispatched directly by the webhook.
  Future<void> initiateTopUp({
    required double amount,
    required String currency,
    required String providerName,
    required String payerIdentity,
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
      final response = await _supabase.rpc('initiate_wallet_topup', params: {
        'p_account_id': state.accountId,
        'p_amount': amount,
        'p_currency': currency,
        'p_provider_name': providerName,
        'p_payer_identity': payerIdentity,
      });

      final paymentUrl = (response as Map<String, dynamic>?)?['payment_url'] as String?;
      
      // If it's M-Pesa or a direct push provider, we might just wait for realtime.
      if (paymentUrl == null || paymentUrl.isEmpty) {
        emit(state.copyWith(topUpStatus: TopUpStatus.waitingPayment));
      } else {
        emit(state.copyWith(topUpStatus: TopUpStatus.success, topUpPaymentUrl: paymentUrl));
      }
    } catch (e) {
      emit(state.copyWith(
        topUpStatus: TopUpStatus.error,
        topUpError:  'Top-up failed: ${e.toFriendlyMessage()}',
      ));
    }
  }

  /// Check status of the latest top-up.
  Future<void> checkTopUpStatus() async {
    final accountId = state.accountId;
    if (accountId == null) return;

    try {
      final row = await _supabase
          .from('wallet_top_ups')
          .select('status')
          .eq('account_id', accountId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (row != null) {
        final status = row['status'] as String?;
        if (status == 'completed' || status == 'success') {
          emit(state.copyWith(topUpStatus: TopUpStatus.success));
          await refresh();
        } else if (status == 'failed') {
          emit(state.copyWith(
            topUpStatus: TopUpStatus.error,
            topUpError: 'Top-up transaction failed.',
          ));
        } else {
          // Still pending, just fetch balance to check if updated
          await _fetchBalances();
        }
      }
    } catch (_) {
      // Fail silently to let the periodic timer retry without distracting the user
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
          .select('id, provider_identity, metadata, platform_payment_providers(provider_name, display_name, logo_url, base_fee_usd, fee_percent)')
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
        withdrawError:  'Could not add payout method: ${e.toFriendlyMessage()}',
      ));
    }
  }

  /// Delete a saved payout method.
  Future<void> deletePayoutMethod(String methodId) async {
    try {
      await _supabase
          .from('account_payment_methods')
          .delete()
          .eq('id', methodId)
          .eq('account_id', state.accountId!);
      await loadPayoutMethods();
    } catch (e) {
      emit(state.copyWith(
        withdrawStatus: WithdrawStatus.error,
        withdrawError: 'Failed to delete method: ${e.toFriendlyMessage()}'
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
        withdrawError:  'Withdrawal failed: ${e.toFriendlyMessage()}',
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
        withdrawError:  'Transfer failed: ${e.toFriendlyMessage()}',
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
    _authSubscription?.cancel();
    _authSubscription = null;
    _balanceChannel?.unsubscribe();
    _balanceChannel = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectDelay = const Duration(seconds: 2);
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
        error: 'Failed to create wallet: ${e.toFriendlyMessage()}',
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
      emit(state.copyWith(isLoading: false, error: 'Failed to set PIN: ${e.toFriendlyMessage()}'));
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
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final hexId = prefs.getString('wallet_webauthn_credential_id');
        if (hexId == null) return false;

        final didAuth = await WebAuthnHelper.authenticateLocalCredential(hexId);
        if (didAuth) {
          emit(state.copyWith(isWalletUnlocked: true));
          return true;
        }
        return false;
      } else {
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
      }
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
    if (useBio && kIsWeb) {
      final hexId = prefs.getString('wallet_webauthn_credential_id');
      if (hexId == null) {
        emit(state.copyWith(useBiometrics: false));
        return;
      }
    }
    emit(state.copyWith(useBiometrics: useBio));
  }

  Future<void> toggleBiometrics(bool enable) async {
    final prefs = await SharedPreferences.getInstance();
    if (enable) {
      if (kIsWeb) {
        final email = _supabase.auth.currentUser?.email ?? 'user@lynk-x';
        final hexId = await WebAuthnHelper.registerLocalCredential(email);
        if (hexId == null) {
          emit(state.copyWith(useBiometrics: false, error: 'WebAuthn registration failed or was cancelled.'));
          return;
        }
        await prefs.setString('wallet_webauthn_credential_id', hexId);
      } else {
        final canCheck = await _localAuth.canCheckBiometrics;
        if (!canCheck) {
          emit(state.copyWith(useBiometrics: false, error: 'Biometrics not available on this device.'));
          return;
        }
      }
    }
    await prefs.setBool('wallet_use_biometrics_v1', enable);
    emit(state.copyWith(useBiometrics: enable, clearError: true));
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
