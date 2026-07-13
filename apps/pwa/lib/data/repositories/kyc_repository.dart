import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps the api.* KYC RPCs (see supabase/schema/12_api/functions/public_rpc/07_kyc_rpc.sql).
/// Mirrors the shape consumed by the web app's verify/onboarding flows so the
/// PWA and web stay on the same requirements/status/submit/history contract.
class KycRepository {
  final SupabaseClient _client;
  KycRepository(this._client);

  /// Dynamic per-country/account-type/tier document & info requirements.
  /// Returns a list of `{ id, type: 'file'|'text', label, subtype?, mandatory, sides?, hint? }`.
  Future<List<Map<String, dynamic>>> getRequirements({
    required String countryCode,
    required String accountType,
    String tierSlug = 'tier_1_basic',
  }) async {
    final result = await _client.schema('api').rpc('get_kyc_requirements', params: {
      'p_country_code': countryCode,
      'p_account_type': accountType,
      'p_tier_slug': tierSlug,
    });
    return List<Map<String, dynamic>>.from(result as List? ?? const []);
  }

  /// Latest verification attempt status for the account, or
  /// `{ status: 'not_started' }` if none exists yet.
  Future<Map<String, dynamic>> getStatus(String accountId) async {
    final result = await _client.schema('api').rpc('get_account_kyc_status', params: {
      'p_account_id': accountId,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  /// Past verification attempts, newest first.
  Future<List<Map<String, dynamic>>> getHistory(String accountId, {int limit = 10}) async {
    final result = await _client.schema('api').rpc('get_account_kyc_history', params: {
      'p_account_id': accountId,
      'p_limit': limit,
    });
    return List<Map<String, dynamic>>.from(result as List? ?? const []);
  }

  /// Submits one verification attempt covering every requirement gathered so
  /// far. The backend rejects a new submission while one is already pending
  /// for the account — surfaced to the caller as a PostgrestException.
  Future<Map<String, dynamic>> submit({
    required String accountId,
    required String tierSlug,
    required String documentType,
    required List<String> uploadedDocs,
    required Map<String, dynamic> piiData,
  }) async {
    final result = await _client.schema('api').rpc('submit_identity_verification', params: {
      'p_account_id': accountId,
      'p_tier_slug': tierSlug,
      'p_document_type': documentType,
      'p_uploaded_docs': uploadedDocs,
      'p_pii_data': piiData,
    });
    return Map<String, dynamic>.from(result as Map);
  }
}
