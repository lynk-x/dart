part of 'feature_flag_cubit.dart';

class FeatureFlagState {
  final List<FeatureFlag> flags;
  final bool isLoading;
  final String? error;
  final String appVersion;

  /// ISO 3166-1 alpha-2 country code for the current user, used for regional
  /// flag evaluation. Null until fetched (treated as "unknown region").
  final String? userCountry;

  const FeatureFlagState({
    this.flags = const [],
    this.isLoading = false,
    this.error,
    this.appVersion = '0.0.0',
    this.userCountry,
  });

  FeatureFlagState copyWith({
    List<FeatureFlag>? flags,
    bool? isLoading,
    String? error,
    String? appVersion,
    String? userCountry,
  }) {
    return FeatureFlagState(
      flags: flags ?? this.flags,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      appVersion: appVersion ?? this.appVersion,
      userCountry: userCountry ?? this.userCountry,
    );
  }
}
