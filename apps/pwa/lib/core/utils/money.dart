/// A monetary amount with an ISO 4217 currency code.
///
/// Wallet state threads currency as a bare `String?` through
/// `WalletState.selectedCurrency` → sheet-local `String _selectedCurrency`,
/// and every sheet formats amounts inline with a different precision
/// (`toStringAsFixed(2)`, `.0`, a `K` suffix). Centralising the symbol and
/// precision rules here makes the currency a real type and keeps formatting
/// in one place.
class Money {
  Money(this.amount, this.currency);

  final double amount;
  final String currency;

  /// Two-decimal formatting for account balances and transaction rows.
  String format({int decimals = 2}) {
    final text = amount.toStringAsFixed(decimals);
    return '$currency $text';
  }

  /// Whole-number formatting for quick-pick amounts and summary rows.
  String formatWhole() => '$currency ${amount.toStringAsFixed(0)}';

  /// Compact formatting for dense lists (e.g. 12000 KES → "12K KES").
  String formatCompact() {
    final abs = amount.abs();
    String body;
    if (abs >= 1000) {
      body = '${(abs / 1000).toStringAsFixed(0)}K';
    } else {
      body = amount.toStringAsFixed(0);
    }
    return '$currency $body';
  }

  @override
  bool operator ==(Object other) =>
      other is Money && amount == other.amount && currency == other.currency;

  @override
  int get hashCode => amount.hashCode ^ currency.hashCode;
}