import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'profile_state.dart';
import '../domain/models/profile_model.dart';

class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit() : super(const ProfileInitial());

  String? get userId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  Future<void> loadProfile() async {
    final uid = userId;
    if (uid == null) {
      emit(const ProfileError('Not authenticated'));
      return;
    }

    emit(const ProfileLoading());
    try {
      final data = await Supabase.instance.client
          .from('user_profile')
          .select()
          .eq('id', uid)
          .single();
      emit(ProfileLoaded(profile: ProfileModel.fromMap(data)));
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  /// Updates the authenticated user's profile.
  ///
  /// Routes editable fields through the `update_my_profile` RPC, which also
  /// handles auth/admin checks and bio/tagline serialization into the `info`
  /// jsonb column. `user_name` is updated separately because the RPC does not
  /// expose it; the schema's `tr_user_profile_security` trigger does not
  /// restrict user_name writes for the row owner.
  Future<void> updateProfile({
    String? fullName,
    String? userName,
    String? bio,
    String? tagline,
    String? countryCode,
  }) async {
    final currentState = state;
    if (currentState is! ProfileLoaded) return;
    final uid = userId;
    if (uid == null) return;

    emit(currentState.copyWith(isUpdating: true));
    try {
      final infoPatch = <String, dynamic>{};
      if (bio != null) infoPatch['bio'] = bio;
      if (tagline != null) infoPatch['tagline'] = tagline;

      // RPC: full_name + avatar_url + info (bio/tagline) + country_code
      final hasRpcUpdate = fullName != null ||
          countryCode != null ||
          infoPatch.isNotEmpty;
      if (hasRpcUpdate) {
        await Supabase.instance.client.rpc('update_my_profile', params: {
          if (fullName != null) 'p_full_name': fullName,
          if (countryCode != null) 'p_country_code': countryCode,
          if (infoPatch.isNotEmpty) 'p_info': infoPatch,
        });
      }

      // user_name is not covered by update_my_profile; direct UPDATE.
      if (userName != null) {
        await Supabase.instance.client
            .from('user_profile')
            .update({'user_name': userName})
            .eq('id', uid);
      }

      final updatedProfile = currentState.profile.copyWith(
        fullName: fullName,
        userName: userName,
        bio: bio,
        tagline: tagline,
        countryCode: countryCode,
      );
      emit(ProfileLoaded(profile: updatedProfile));
    } catch (e) {
      emit(currentState.copyWith(isUpdating: false, error: e.toString()));
    }
  }

  // XFile works on both web (blob URL) and mobile (file path).
  // Reads bytes so we can use uploadBinary, which is platform-agnostic.
  Future<void> uploadAvatar(XFile imageFile) async {
    final currentState = state;
    if (currentState is! ProfileLoaded || userId == null) return;
    final uid = userId!;

    emit(currentState.copyWith(isUpdating: true));
    try {
      final bytes = await imageFile.readAsBytes();
      final ext = imageFile.name.split('.').last.toLowerCase();
      final fileName = '$uid-${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = 'avatars/$fileName';

      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: 'image/$ext'),
          );

      final imageUrl =
          Supabase.instance.client.storage.from('avatars').getPublicUrl(path);

      final updatedProfile = currentState.profile.copyWith(avatarUrl: imageUrl);

      await Supabase.instance.client
          .from('user_profile')
          .update({'avatar_url': imageUrl}).eq('id', uid);

      emit(ProfileLoaded(profile: updatedProfile));
    } catch (e) {
      debugPrint('[ProfileCubit] uploadAvatar failed: $e');
      emit(currentState.copyWith(isUpdating: false, error: e.toString()));
    }
  }

  Future<void> removeAvatar() async {
    final currentState = state;
    if (currentState is! ProfileLoaded || userId == null) return;
    final uid = userId!;

    emit(currentState.copyWith(isUpdating: true));
    try {
      await Supabase.instance.client
          .from('user_profile')
          .update({'avatar_url': null}).eq('id', uid);

      final updatedProfile = currentState.profile.copyWith(clearAvatarUrl: true);

      emit(ProfileLoaded(profile: updatedProfile));
    } catch (e) {
      debugPrint('[ProfileCubit] removeAvatar failed: $e');
      emit(currentState.copyWith(isUpdating: false, error: e.toString()));
    }
  }

  Future<void> deleteAccount() async {
    final currentState = state;
    if (currentState is! ProfileLoaded) return;

    emit(currentState.copyWith(isUpdating: true));
    try {
      await Supabase.instance.client.rpc('delete_user_account');
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      emit(currentState.copyWith(isUpdating: false, error: e.toString()));
    }
  }

  /// Monotonic request id; in-flight RPCs check this against the latest
  /// before applying their result, so a slow earlier response cannot
  /// clobber a faster later one.
  int _usernameRequestId = 0;

  Future<void> checkUsernameAvailability(String username) async {
    final currentState = state;
    if (currentState is! ProfileLoaded) return;

    final requestId = ++_usernameRequestId;
    emit(currentState.copyWith(isCheckingUsername: true, isUsernameAvailable: null));
    try {
      final response = await Supabase.instance.client.rpc(
        'is_username_available',
        params: {'username_to_check': username},
      );
      // Discard stale responses.
      if (requestId != _usernameRequestId) return;
      // Re-read state in case it changed during the await.
      final next = state;
      if (next is! ProfileLoaded) return;
      emit(next.copyWith(
        isCheckingUsername: false,
        isUsernameAvailable: response as bool,
      ));
    } catch (e) {
      if (requestId != _usernameRequestId) return;
      final next = state;
      if (next is! ProfileLoaded) return;
      emit(next.copyWith(isCheckingUsername: false));
    }
  }

  void reset() => emit(const ProfileInitial());
}
