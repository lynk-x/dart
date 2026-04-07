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

  const ProfileLoaded({
    required this.profile,
    this.isUpdating = false,
    this.error,
  });

  ProfileLoaded copyWith({
    ProfileModel? profile,
    bool? isUpdating,
    String? error,
  }) {
    return ProfileLoaded(
      profile: profile ?? this.profile,
      isUpdating: isUpdating ?? this.isUpdating,
      error: error,
    );
  }
}

class ProfileError extends ProfileState {
  final String message;
  const ProfileError(this.message);
}
