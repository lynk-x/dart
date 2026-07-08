import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:lynk_core/core.dart';
import '../../src/utils/image_conversion.dart';
import '../data/repositories/profile_repository.dart';

class ProfileCubit extends Cubit<ProfileState> {
  final ProfileRepository _repo;
  ProfileCubit(this._repo) : super(const ProfileInitial());

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
      final profile = await _repo.getProfile(uid);
      emit(ProfileLoaded(profile: profile));
    } catch (e) {
      emit(ProfileError(e.toFriendlyMessage()));
    }
  }

  /// Updates the authenticated user's profile.
  ///
  /// Routes editable fields through the `update_profile` RPC, which also
  /// handles auth/admin checks and bio/tagline serialization into the `info`
  /// jsonb column. `user_name` is updated separately because the RPC does not
  /// expose it; the schema's `tr_user_profile_security` trigger does not
  /// restrict user_name writes for the row owner.
  Future<void> updateProfile({
    String? fullName,
    String? userName,
    String? gender,
    DateTime? dateOfBirth,
    String? countryCode,
  }) async {
    final currentState = state;
    if (currentState is! ProfileLoaded) return;
    final uid = userId;
    if (uid == null) return;

    emit(currentState.copyWith(isUpdating: true));
    try {
      // RPC: full_name + avatar_url + country_code + gender + date_of_birth
      final hasRpcUpdate = fullName != null ||
          countryCode != null ||
          gender != null ||
          dateOfBirth != null;
      if (hasRpcUpdate) {
        await _repo.updateProfile(
          fullName: fullName,
          gender: gender,
          dateOfBirth: dateOfBirth,
          countryCode: countryCode,
        );
      }

      // user_name is not covered by update_my_profile; direct UPDATE via repo.
      if (userName != null) {
        await _repo.updateUserName(uid, userName);
      }

      final updatedProfile = currentState.profile.copyWith(
        fullName: fullName,
        userName: userName,
        gender: gender,
        dateOfBirth: dateOfBirth,
        countryCode: countryCode,
      );
      emit(ProfileLoaded(profile: updatedProfile));
    } catch (e) {
      debugPrint('[ProfileCubit] updateProfile failed: $e');
      emit(currentState.copyWith(isUpdating: false, error: e.toFriendlyMessage()));
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
      final rawBytes = await imageFile.readAsBytes();
      final rawExt = imageFile.name.split('.').last.toLowerCase();
      final (bytes, ext) = await convertImageToWebP(rawBytes, rawExt);

      final imageUrl = await _repo.uploadAvatar(uid, bytes, ext);
      await _repo.updateAvatarUrl(uid, imageUrl);

      final updatedProfile = currentState.profile.copyWith(avatarUrl: imageUrl);
      emit(ProfileLoaded(profile: updatedProfile));
    } catch (e) {
      debugPrint('[ProfileCubit] uploadAvatar failed: $e');
      emit(currentState.copyWith(isUpdating: false, error: e.toFriendlyMessage()));
    }
  }

  Future<void> removeAvatar() async {
    final currentState = state;
    if (currentState is! ProfileLoaded || userId == null) return;
    final uid = userId!;

    emit(currentState.copyWith(isUpdating: true));
    try {
      await _repo.updateAvatarUrl(uid, null);

      final updatedProfile = currentState.profile.copyWith(clearAvatarUrl: true);
      emit(ProfileLoaded(profile: updatedProfile));
    } catch (e) {
      debugPrint('[ProfileCubit] removeAvatar failed: $e');
      emit(currentState.copyWith(isUpdating: false, error: e.toFriendlyMessage()));
    }
  }

  Future<void> deleteAccount() async {
    final currentState = state;
    if (currentState is! ProfileLoaded) return;

    emit(currentState.copyWith(isUpdating: true));
    try {
      await _repo.deleteAccount();
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      emit(currentState.copyWith(isUpdating: false, error: e.toFriendlyMessage()));
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
      final available = await _repo.isUsernameAvailable(username);
      // Discard stale responses.
      if (requestId != _usernameRequestId) return;
      // Re-read state in case it changed during the await.
      final next = state;
      if (next is! ProfileLoaded) return;
      emit(next.copyWith(
        isCheckingUsername: false,
        isUsernameAvailable: available,
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
