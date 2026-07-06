import 'package:supabase_flutter/supabase_flutter.dart';

class WalletRepository {
  final SupabaseClient _client;
  WalletRepository(this._client);

  Future<List<Map<String, dynamic>>> getBalances(String accountId) async {
    final data = await _client
        .schema('api')
        .from('v1_wallet_balances')
        .select('currency, cash_balance, escrow_balance, credit_balance')
        .eq('account_id', accountId)
        .order('currency');
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>?> getWalletBalance(String accountId, String currency) async {
    return await _client
        .schema('api')
        .from('v1_wallet_balances')
        .select('account_id, currency, cash_balance, escrow_balance, credit_balance, updated_at')
        .eq('account_id', accountId)
        .eq('currency', currency)
        .maybeSingle();
  }

  Future<List<Map<String, dynamic>>> getTimeline(
    String accountId, {
    int limit = 30,
    int offset = 0,
    String? currency,
  }) async {
    var query = _client
        .schema('api')
        .from('v1_wallet_timeline')
        .select('id, entry_type, category, reason, amount, currency, status, event_id, account_id, reference, created_at')
        .eq('account_id', accountId);

    if (currency != null) query = query.eq('currency', currency);

    final data = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>> initiateTopUp({
    required String accountId,
    required double amount,
    required String currency,
    required String provider,
  }) async {
    final result = await _client.schema('api').rpc('initiate_wallet_topup', params: {
      'p_account_id': accountId,
      'p_amount': amount,
      'p_currency': currency,
      'p_provider': provider,
    });
    return result as Map<String, dynamic>;
  }

  /// Requests a payout against a saved payout method
  /// (finance.account_payment_methods row — see api.request_account_payout).
  Future<Map<String, dynamic>> requestPayout({
    required String accountId,
    required double amount,
    required String currency,
    required String payoutMethodId,
  }) async {
    final result =
        await _client.schema('api').rpc('request_account_payout', params: {
      'p_account_id': accountId,
      'p_amount': amount,
      'p_payout_method_id': payoutMethodId,
      'p_currency': currency,
    });
    return result as Map<String, dynamic>;
  }

  RealtimeChannel subscribeToBalance(
    String accountId,
    void Function(PostgresChangePayload) callback,
  ) {
    return _client
        .channel('wallet_balance:$accountId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'finance',
          table: 'account_wallets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'account_id',
            value: accountId,
          ),
          callback: callback,
        );
  }
}
