import 'package:equatable/equatable.dart';
import 'package:lynk_x/presentation/features/wallet/models/wallet_model.dart';

/// Status of a wallet top-up submission.
enum TopUpStatus { idle, submitting, success, error }

/// Immutable state for [WalletCubit].
class WalletState extends Equatable {
  // ── Balances ───────────────────────────────────────────────────────────────
  /// All wallets for the current account (multi-currency supported).
  final List<WalletBalance> balances;

  // ── Transactions ──────────────────────────────────────────────────────────
  /// Paged transaction history, newest first.
  final List<WalletTransaction> transactions;

  /// Whether there are more transactions to fetch (pagination).
  final bool hasMore;

  // ── Loading / Error ────────────────────────────────────────────────────────
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  // ── Top-up Flow ────────────────────────────────────────────────────────────
  final TopUpStatus topUpStatus;
  final String? topUpError;
  final String? topUpPaymentUrl; // Redirect URL returned by the payment gateway

  const WalletState({
    this.balances        = const [],
    this.transactions    = const [],
    this.hasMore         = true,
    this.isLoading       = false,
    this.isLoadingMore   = false,
    this.error,
    this.topUpStatus     = TopUpStatus.idle,
    this.topUpError,
    this.topUpPaymentUrl,
  });

  WalletState copyWith({
    List<WalletBalance>? balances,
    List<WalletTransaction>? transactions,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
    TopUpStatus? topUpStatus,
    String? topUpError,
    bool clearTopUpError = false,
    String? topUpPaymentUrl,
    bool clearPaymentUrl = false,
  }) {
    return WalletState(
      balances:        balances        ?? this.balances,
      transactions:    transactions    ?? this.transactions,
      hasMore:         hasMore         ?? this.hasMore,
      isLoading:       isLoading       ?? this.isLoading,
      isLoadingMore:   isLoadingMore   ?? this.isLoadingMore,
      error:           clearError      ? null : error      ?? this.error,
      topUpStatus:     topUpStatus     ?? this.topUpStatus,
      topUpError:      clearTopUpError ? null : topUpError ?? this.topUpError,
      topUpPaymentUrl: clearPaymentUrl ? null : topUpPaymentUrl ?? this.topUpPaymentUrl,
    );
  }

  @override
  List<Object?> get props => [
    balances, transactions, hasMore,
    isLoading, isLoadingMore, error,
    topUpStatus, topUpError, topUpPaymentUrl,
  ];
}
