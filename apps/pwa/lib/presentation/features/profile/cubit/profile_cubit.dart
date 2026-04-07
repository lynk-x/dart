import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_state.dart';
import 'package:lynk_x/presentation/features/profile/models/profile_model.dart';

class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit() : super(const ProfileInitial());

  String get userId => Supabase.instance.client.auth.currentUser!.id;

  Future<void> loadProfile() async {
    emit(const ProfileLoading());
    try {
      final data = await Supabase.instance.client
          .from('user_profile')
          .select()
          .eq('id', userId)
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
          .eq('id', userId);

      emit(ProfileLoaded(profile: updatedProfile));
    } catch (e) {
      emit(currentState.copyWith(isUpdating: false, error: e.toString()));
    }
  }

  Future<void> uploadAvatar(File imageFile) async {
    final currentState = state;
    if (currentState is! ProfileLoaded) return;

    emit(currentState.copyWith(isUpdating: true));
    try {
      final fileExt = imageFile.path.split('.').last;
      final fileName =
          '$userId-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final path = 'avatars/$fileName';

      await Supabase.instance.client.storage
          .from('profiles') // Ensure this bucket exists
          .upload(path, imageFile);

      final imageUrl =
          Supabase.instance.client.storage.from('profiles').getPublicUrl(path);

      final updatedProfile = currentState.profile.copyWith(avatarUrl: imageUrl);

      await Supabase.instance.client
          .from('user_profile')
          .update({'avatar_url': imageUrl}).eq('id', userId);

      emit(ProfileLoaded(profile: updatedProfile));
    } catch (e) {
      emit(currentState.copyWith(isUpdating: false, error: e.toString()));
    }
  }

  Future<void> deleteAccount() async {
    final currentState = state;
    if (currentState is! ProfileLoaded) return;

    emit(currentState.copyWith(isUpdating: true));
    try {
      // Call the RPC to delete the profile data server-side
      await Supabase.instance.client.rpc('delete_user_account');

      // Sign out immediately
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      emit(currentState.copyWith(isUpdating: false, error: e.toString()));
    }
  }
}
