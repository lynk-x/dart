import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
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
        .from('user_profile')
        .select('id, email, avatar_url, user_name, full_name, country_code, is_premium, info')
        .eq('id', userId)
        .single();
    return ProfileModel.fromMap(data);
  }

  Future<void> updateProfile({
    String? fullName,
    String? countryCode,
    Map<String, dynamic>? info,
  }) async {
    await _client.rpc('update_profile', params: {
      if (fullName != null) 'p_full_name': fullName,
      if (countryCode != null) 'p_country_code': countryCode,
      if (info != null) 'p_info': info,
    });
  }

  Future<void> updateUserName(String userId, String userName) async {
    await _client
        .from('user_profile')
        .update({'user_name': userName})
        .eq('id', userId);
  }

  /// Uploads an avatar image to the user-scoped folder in the `avatars` bucket.
  ///
  /// Path convention: `{user_id}/avatar.{ext}` — must match the RLS policy
  /// on the `avatars` storage bucket which restricts writes to `{uid}/*`.
  Future<String> uploadAvatar(
      String userId, Uint8List bytes, String ext) async {
    final path = '$userId/avatar.$ext';

    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
        );

    return _client.storage.from('avatars').getPublicUrl(path);
  }

  Future<void> updateAvatarUrl(String userId, String? avatarUrl) async {
    await _client
        .from('user_profile')
        .update({'avatar_url': avatarUrl})
        .eq('id', userId);
  }

  Future<void> deleteAccount() async {
    await _client.rpc('shred_user_data');
  }

  Future<bool> isUsernameAvailable(String username) async {
    final result = await _client.rpc(
      'is_username_available',
      params: {'username_to_check': username},
    );
    return result as bool;
  }
}
