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

  Future<void> updateProfile({
    String? fullName,
    String? userName,
    String? bio,
    String? tagline,
  }) async {
    final currentState = state;
    if (currentState is! ProfileLoaded) return;
    final uid = userId;
    if (uid == null) return;

    emit(currentState.copyWith(isUpdating: true));
    try {
      final updatedProfile = currentState.profile.copyWith(
        fullName: fullName,
        userName: userName,
        bio: bio,
        tagline: tagline,
      );

      await Supabase.instance.client
          .from('user_profile')
          .update(updatedProfile.toMap())
          .eq('id', uid);

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
          .from('profiles')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: 'image/$ext'),
          );

      final imageUrl =
          Supabase.instance.client.storage.from('profiles').getPublicUrl(path);

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
}
