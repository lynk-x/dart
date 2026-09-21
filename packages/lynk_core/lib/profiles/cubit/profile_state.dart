import '../domain/models/profile_model.dart';

abstract class ProfileState {
  const ProfileState();
}

class ProfileInitial extends ProfileState {
  const ProfileInitial();
}

class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

class ProfileLoaded extends ProfileState {
  final ProfileModel profile;
  final bool isUpdating;
  final String? error;
  final bool? isUsernameAvailable;
  final bool isCheckingUsername;
  final bool isRegeneratingUsername;

  const ProfileLoaded({
    required this.profile,
    this.isUpdating = false,
    this.error,
    this.isUsernameAvailable,
    this.isCheckingUsername = false,
    this.isRegeneratingUsername = false,
  });

  ProfileLoaded copyWith({
    ProfileModel? profile,
    bool? isUpdating,
    String? error,
    bool? isUsernameAvailable,
    bool? isCheckingUsername,
    bool? isRegeneratingUsername,
  }) {
    return ProfileLoaded(
      profile: profile ?? this.profile,
      isUpdating: isUpdating ?? this.isUpdating,
      error: error,
      isUsernameAvailable: isUsernameAvailable ?? this.isUsernameAvailable,
      isCheckingUsername: isCheckingUsername ?? this.isCheckingUsername,
      isRegeneratingUsername:
          isRegeneratingUsername ?? this.isRegeneratingUsername,
    );
  }
}

class ProfileError extends ProfileState {
  final String message;
  const ProfileError(this.message);
}
