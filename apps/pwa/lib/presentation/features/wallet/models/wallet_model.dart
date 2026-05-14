import 'package:equatable/equatable.dart';

// ===== Wallet Model =====

/// Represents a single account wallet fetched from the database.
class WalletBalance extends Equatable {
  final String currency;
  final double cashBalance;
  final double pendingBalance;
  final double creditBalance;

  const WalletBalance({
    required this.currency,
    required this.cashBalance,
    required this.pendingBalance,
    required this.creditBalance,
  });

  factory WalletBalance.fromMap(Map<String, dynamic> map) {
    return WalletBalance(
      currency: map['currency'] as String,
      cashBalance: (map['cash_balance'] as num).toDouble(),
      pendingBalance: (map['escrow_balance'] as num? ?? 0).toDouble(),
      creditBalance: (map['credit_balance'] as num? ?? 0).toDouble(),
    );
  }

  @override
  List<Object?> get props => [currency, cashBalance, pendingBalance, creditBalance];
}

/// Represents a single entry in the unified wallet timeline feed.
/// Sourced from api.v1_wallet_timeline (transactions + top-ups + payouts).
class WalletTransaction extends Equatable {
  final String id;
  final String entryType;  // 'transaction' | 'top_up' | 'payout'
  final String category;   // 'incoming' | 'outgoing'
  final String reason;
  final double amount;
  final String currency;
  final String status;
  final String? eventId;
  final String? reference;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.entryType,
    required this.category,
    required this.reason,
    required this.amount,
    required this.currency,
    required this.status,
    this.eventId,
    this.reference,
    required this.createdAt,
  });

  factory WalletTransaction.fromMap(Map<String, dynamic> map) {
    return WalletTransaction(
      id:        map['id'] as String,
      entryType: map['entry_type'] as String? ?? 'transaction',
      category:  map['category'] as String,
      reason:    map['reason'] as String,
      amount:    (map['amount'] as num).toDouble(),
      currency:  map['currency'] as String,
      status:    map['status'] as String,
      eventId:   map['event_id'] as String?,
      reference: map['reference'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id];
}
