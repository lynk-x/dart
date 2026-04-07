import 'package:equatable/equatable.dart';

// ===== Wallet Model =====

/// Represents a single account wallet fetched from the database.
class WalletBalance extends Equatable {
  final String currency;
  final double balance;
  final double pendingBalance;

  const WalletBalance({
    required this.currency,
    required this.balance,
    required this.pendingBalance,
  });

  factory WalletBalance.fromMap(Map<String, dynamic> map) {
    return WalletBalance(
      currency: map['currency'] as String,
      balance: (map['balance'] as num).toDouble(),
      pendingBalance: (map['pending_balance'] as num? ?? 0).toDouble(),
    );
  }

  @override
  List<Object?> get props => [currency, balance, pendingBalance];
}

/// Represents a single wallet transaction for the activity feed.
class WalletTransaction extends Equatable {
  final String id;
  final String category;
  final String reason;
  final double amount;
  final String currency;
  final String status;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  const WalletTransaction({
    required this.id,
    required this.category,
    required this.reason,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createdAt,
    required this.metadata,
  });

  factory WalletTransaction.fromMap(Map<String, dynamic> map) {
    return WalletTransaction(
      id:         map['id'] as String,
      category:   map['category'] as String,
      reason:     map['reason'] as String,
      amount:     (map['amount'] as num).toDouble(),
      currency:   map['currency'] as String,
      status:     map['status'] as String,
      createdAt:  DateTime.parse(map['created_at'] as String),
      metadata:   (map['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  @override
  List<Object?> get props => [id];
}
