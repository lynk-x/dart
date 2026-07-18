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

  /// Keyset-paginated: pass the (created_at, id) of the last row from the
  /// previous page as [beforeCreatedAt]/[beforeId] to fetch the next page.
  /// Omit both for the first page.
  Future<List<Map<String, dynamic>>> getTimeline(
    String accountId, {
    int limit = 30,
    String? currency,
    String? beforeCreatedAt,
    String? beforeId,
  }) async {
    var query = _client
        .schema('api')
        .from('v1_wallet_timeline')
        .select('id, entry_type, category, reason, amount, currency, status, event_id, account_id, reference, created_at')
        .eq('account_id', accountId);

    if (currency != null) query = query.eq('currency', currency);

    if (beforeCreatedAt != null && beforeId != null) {
      // (created_at, id) < (cursor) — matches the DESC ordering below.
      query = query.or(
        'created_at.lt.$beforeCreatedAt,'
        'and(created_at.eq.$beforeCreatedAt,id.lt.$beforeId)',
      );
    }

    final data = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<String?> getAccountReference(String accountId) async {
    final row = await _client
        .schema('api')
        .from('v1_accounts')
        .select('reference')
        .eq('id', accountId)
        .maybeSingle();
    return row?['reference'] as String?;
  }

  Future<Map<String, dynamic>?> resolveRecipientDetails(String identifier) async {
    final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(identifier);
    final query = _client.schema('api').from('v1_accounts').select('id, reference, display_name');
    return isUuid
        ? await query.eq('id', identifier).maybeSingle()
        : await query.eq('reference', identifier).maybeSingle();
  }

  Future<Map<String, dynamic>> initiateTopUp({
    required String accountId,
    required double amount,
    required String currency,
    required String providerName,
    required String payerIdentity,
  }) async {
    final result = await _client.schema('api').rpc('initiate_wallet_topup', params: {
      'p_account_id': accountId,
      'p_amount': amount,
      'p_currency': currency,
      'p_provider_name': providerName,
      'p_payer_identity': payerIdentity,
    });
    return (result as Map<String, dynamic>?) ?? const {};
  }

  Future<String?> getLatestTopUpStatus(String accountId) async {
    final row = await _client
        .schema('api')
        .from('v1_wallet_top_ups')
        .select('status')
        .eq('account_id', accountId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row?['status'] as String?;
  }

  /// Fetches the caller's saved payout methods for [accountId], reshaped
  /// from the v1 view's denormalized provider columns into the embedded
  /// `platform_payment_providers` layout the wallet widgets consume.
  Future<List<Map<String, dynamic>>> getPayoutMethods(String accountId) async {
    final rawMethods = await _client
        .schema('api')
        .from('v1_account_payment_methods')
        .select(
            'id, metadata, provider_name, provider_display_name, provider_logo_url, provider_base_fee_usd, provider_fee_percent')
        .eq('account_id', accountId);

    return rawMethods.map((m) => <String, dynamic>{
          'id': m['id'],
          'metadata': m['metadata'],
          'provider_identity': (m['metadata']?['label'] as String?) ?? '••••',
          'platform_payment_providers': <String, dynamic>{
            'provider_name': m['provider_name'],
            'display_name': m['provider_display_name'],
            'logo_url': m['provider_logo_url'],
            'base_fee_usd': m['provider_base_fee_usd'],
            'fee_percent': m['provider_fee_percent'],
          },
        }).toList();
  }

  /// Latest approved KYC tier for [accountId], or null if unverified.
  Future<String?> getApprovedKycTier(String accountId) async {
    final kycRow = await _client
        .schema('api')
        .from('v1_identity_verifications')
        .select('kyc_tier, status')
        .eq('account_id', accountId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (kycRow != null && kycRow['status'] == 'approved') {
      return kycRow['kyc_tier'] as String?;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getActivePaymentProviders() async {
    final response = await _client
        .schema('api')
        .from('v1_platform_payment_providers')
        .select('id, provider_name, display_name, logo_url, supports_outbound, status, ui_config')
        .eq('supports_outbound', true)
        .order('display_name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> addPayoutMethod({
    required String providerName,
    required String identity,
    required String label,
  }) async {
    await _client.schema('api').rpc('add_payout_method', params: {
      'p_provider_name': providerName,
      'p_identity': identity,
      'p_label': label,
    });
  }

  Future<void> deletePayoutMethod(String methodId) async {
    // Ownership/billing-permission check happens in the RPC.
    await _client.schema('api').rpc('delete_payout_method', params: {'p_method_id': methodId});
  }

  Future<void> requestWithdrawal({
    required double amount,
    required String currency,
    required String payoutMethodId,
    required String pinHash,
  }) async {
    await _client.schema('api').rpc('request_account_withdrawal', params: {
      'p_account_id': null,
      'p_amount': amount,
      'p_currency': currency,
      'p_payout_method_id': payoutMethodId,
      'p_pin_hash': pinHash,
    });
  }

  Future<void> transferFunds({
    required double amount,
    required String currency,
    required String recipientAccountId,
    required String pinHash,
  }) async {
    await _client.schema('api').rpc('transfer_funds', params: {
      'p_amount': amount,
      'p_currency': currency,
      'p_recipient_account_id': recipientAccountId,
      'p_pin_hash': pinHash,
    });
  }

  Future<void> createWallet(String currency) async {
    await _client.schema('api').rpc('create_wallet', params: {'p_currency': currency});
  }

  Future<bool> hasWalletPinSet(String userId) async {
    final res = await _client
        .schema('api')
        .from('v1_profiles')
        .select('wallet_pin_hash')
        .eq('id', userId)
        .single();
    return res['wallet_pin_hash'] != null;
  }

  Future<void> setWalletPin(String pinHash) async {
    await _client.schema('api').rpc('set_wallet_pin', params: {'p_pin_hash': pinHash});
  }

  Future<bool> verifyWalletPin(String pinHash) async {
    return await _client.schema('api').rpc('verify_wallet_pin', params: {'p_pin_hash': pinHash}) as bool;
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
