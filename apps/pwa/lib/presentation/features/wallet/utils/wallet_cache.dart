import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lynk_x/presentation/features/wallet/models/wallet_model.dart';

/// Local SharedPreferences cache for wallet balances/transactions, used only
/// to paint a non-empty screen instantly on cold start before the live fetch
/// completes. Never a source of truth — every read here is followed by a
/// live fetch that overwrites it.
class WalletCache {
  const WalletCache();

  Future<List<WalletBalance>?> loadBalances() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final balancesStr = prefs.getString('cached_balances');
      if (balancesStr == null) return null;
      final decoded = jsonDecode(balancesStr) as List;
      return decoded.map((e) => WalletBalance.fromMap(Map<String, dynamic>.from(e))).toList();
    } catch (e, stack) {
      // Corrupted/stale cache is safe to ignore functionally (falls through
      // to a live fetch), but log so a systemic decode failure isn't invisible.
      debugPrint('[WalletCache] loadBalances error: $e\n$stack');
      return null;
    }
  }

  Future<List<WalletTransaction>?> loadTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final txStr = prefs.getString('cached_transactions');
      if (txStr == null) return null;
      final decoded = jsonDecode(txStr) as List;
      return decoded.map((e) => WalletTransaction.fromMap(Map<String, dynamic>.from(e))).toList();
    } catch (e, stack) {
      debugPrint('[WalletCache] loadTransactions error: $e\n$stack');
      return null;
    }
  }

  Future<void> saveBalances(List<WalletBalance> balances) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(balances.map((b) => {
            'currency': b.currency,
            'cash_balance': b.cashBalance,
            'escrow_balance': b.pendingBalance,
            'credit_balance': b.creditBalance,
          }).toList());
      await prefs.setString('cached_balances', encoded);
    } catch (e, stack) {
      debugPrint('[WalletCache] saveBalances error: $e\n$stack');
    }
  }

  Future<void> saveTransactions(List<WalletTransaction> txs) async {
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
    } catch (e, stack) {
      debugPrint('[WalletCache] saveTransactions error: $e\n$stack');
    }
  }
}
