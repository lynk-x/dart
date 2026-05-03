import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/profile_model.dart';

class ProfileRepository {
  final SupabaseClient _client;
  ProfileRepository(this._client);

  Future<ProfileModel> getProfile(String userId) async {
    final data = await _client
        .from('user_profile')
        .select()
        .eq('id', userId)
        .single();
    return ProfileModel.fromMap(data);
  }

  Future<void> updateProfile({
    String? fullName,
    String? countryCode,
    Map<String, dynamic>? info,
  }) async {
    await _client.rpc('update_my_profile', params: {
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

  Future<String> uploadAvatar(
      String userId, Uint8List bytes, String ext) async {
    final fileName = '$userId-${DateTime.now().millisecondsSinceEpoch}.$ext';
    final path = 'avatars/$fileName';

    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: 'image/$ext'),
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
    await _client.rpc('delete_user_account');
  }

  Future<bool> isUsernameAvailable(String username) async {
    final result = await _client.rpc(
      'is_username_available',
      params: {'username_to_check': username},
    );
    return result as bool;
  }
}
