import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_io/io.dart';
import 'package:lynk_core/core.dart';

class ProfileRepository {
  final SupabaseClient _client;
  ProfileRepository(this._client);

  /// Fetches the user's profile by their auth UID.
  ///
  /// Only selects columns consumed by [ProfileModel.fromMap]; avoids
  /// pulling sensitive fields (embedding, fts, strikes, etc.).
  Future<ProfileModel> getProfile(String userId) async {
    final data = await _client
        .schema('api')
        .from('v1_profiles')
        .select('id, email, avatar_url, user_name, full_name, country_code, is_premium, bio, tagline, reference, phone_number, gender, date_of_birth')
        .eq('id', userId)
        .single();

    String? targetAccountId;
    String? accountStatus;

    try {
      final primaryAccountData = await _client
          .schema('api')
          .from('v1_account_memberships')
          .select('account_id')
          .eq('is_primary', true)
          .maybeSingle();
      if (primaryAccountData != null) {
        targetAccountId = primaryAccountData['account_id'] as String?;
      }
    } catch (_) {
      // Fallback
    }

    String? accountReference;
    if (targetAccountId != null) {
      try {
        final accountData = await _client
            .schema('api')
            .from('v1_accounts')
            .select('reference, is_active')
            .eq('id', targetAccountId)
            .maybeSingle();
        if (accountData != null) {
          accountReference = accountData['reference'] as String?;
          final isActive = accountData['is_active'] as bool? ?? false;
          accountStatus = isActive ? 'active' : 'inactive';
        }
      } catch (_) {
        // Fallback
      }
    }

    return ProfileModel.fromMap(
      data,
      accountReference: accountReference,
      accountStatus: accountStatus,
    );
  }

  Future<void> updateProfile({
    String? fullName,
    String? userName,
    String? countryCode,
    Map<String, dynamic>? info,
    String? gender,
    DateTime? dateOfBirth,
  }) async {
    await _client.schema('api').rpc('update_profile', params: {
      if (fullName != null) 'p_full_name': fullName,
      if (userName != null) 'p_user_name': userName,
      if (countryCode != null) 'p_country_code': countryCode,
      if (info != null) 'p_info': info,
      if (gender != null) 'p_gender': gender,
      if (dateOfBirth != null) 'p_date_of_birth': dateOfBirth.toIso8601String().split('T')[0],
    });
  }

  Future<void> updateUserName(String userId, String userName) async {
    await _client.schema('api').rpc('update_profile', params: {
      'p_user_name': userName,
    });
  }

  /// Uploads an avatar image to the user-scoped folder in the `avatars` bucket.
  ///
  /// Path convention: `{user_id}/avatar.{ext}` — must match the RLS policy
  /// on the `avatars` storage bucket which restricts writes to `{uid}/*`.
  Future<String> uploadAvatar(
      String userId, Uint8List bytes, String ext) async {
    final fileName = 'avatar.$ext';
    final mimeType = 'image/$ext';

    // 1. Request presigned upload URL from Edge Function
    final uploadResponse = await _client.functions.invoke(
      'media-signer',
      body: {
        'action': 'upload',
        'folder': 'avatars',
        'filename': fileName,
        'contentType': mimeType,
        'mediaType': 'image',
      },
    );

    if (uploadResponse.status != 200) {
      throw Exception('Failed to get presigned upload URL');
    }

    final uploadData = uploadResponse.data;
    final uploadUrl = uploadData['uploadUrl'] as String;
    final fileKey = uploadData['fileKey'] as String;

    // 2. Upload to R2 using HttpClient from universal_io
    final httpClient = HttpClient();
    try {
      final request = await httpClient.putUrl(Uri.parse(uploadUrl));
      request.headers.set('content-type', mimeType);
      request.add(bytes);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Failed to upload avatar to R2: ${response.statusCode}');
      }
    } finally {
      httpClient.close();
    }

    // 3. Return the public CDN URL
    return 'https://cdn.lynk-x.app/$fileKey';
  }

  Future<void> updateAvatarUrl(String userId, String? avatarUrl) async {
    await _client.schema('api').rpc('update_profile', params: {
      'p_avatar_url': avatarUrl,
    });
  }

  Future<void> deleteAccount() async {
    await _client.schema('api').rpc('shred_user_data');
  }

  Future<bool> isUsernameAvailable(String username) async {
    final result = await _client.schema('api').rpc(
      'is_username_available',
      params: {'username_to_check': username},
    );
    return result as bool;
  }
}
