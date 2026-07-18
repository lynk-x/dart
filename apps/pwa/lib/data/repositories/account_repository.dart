import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves the caller's personal account — shared by any feature that needs
/// "the current user's own account_id" (wallet, KYC, etc.) so this lookup
/// has one definition instead of drifting per-cubit.
class AccountRepository {
  final SupabaseClient _client;
  AccountRepository(this._client);

  /// Resolves the oldest 'owner' membership account_id for [userId] — this
  /// is the user's personal account (as opposed to any organizer/advertiser
  /// account they may also belong to).
  Future<String?> resolveOwnerAccountId(String userId) async {
    final row = await _client
        .schema('api')
        .from('v1_account_memberships')
        .select('account_id')
        .eq('user_id', userId)
        .eq('role_slug', 'owner')
        .order('created_at', ascending: true)
        .limit(1)
        .maybeSingle();
    return row?['account_id'] as String?;
  }
}
