part of 'feature_flag_cubit.dart';

class FeatureFlagState {
  final List<FeatureFlag> flags;
  final bool isLoading;
  final String? error;
  final String appVersion;

  const FeatureFlagState({
    this.flags = const [],
    this.isLoading = false,
    this.error,
    this.appVersion = '0.0.0',
  });

  FeatureFlagState copyWith({
    List<FeatureFlag>? flags,
    bool? isLoading,
    String? error,
    String? appVersion,
  }) {
    return FeatureFlagState(
      flags: flags ?? this.flags,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      appVersion: appVersion ?? this.appVersion,
    );
  }
}
