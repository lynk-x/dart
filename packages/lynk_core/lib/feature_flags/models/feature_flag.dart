import 'package:equatable/equatable.dart';

class FeatureFlag extends Equatable {
  final String key;
  final bool isEnabled;
  final String? description;
  final List<String> platforms;
  final Map<String, dynamic> exclusionRules;
  final int rolloutPercent;

  const FeatureFlag({
    required this.key,
    required this.isEnabled,
    this.description,
    required this.platforms,
    required this.exclusionRules,
    required this.rolloutPercent,
  });

  factory FeatureFlag.fromMap(Map<String, dynamic> map) {
    return FeatureFlag(
      key: map['key'] as String,
      isEnabled: map['is_enabled'] as bool? ?? false,
      description: map['description'] as String?,
      platforms: List<String>.from(map['platforms'] ?? []),
      exclusionRules: map['exclusion_rules'] as Map<String, dynamic>? ?? {},
      rolloutPercent: map['rollout_percent'] as int? ?? 100,
    );
  }

  @override
  List<Object?> get props => [
        key,
        isEnabled,
        description,
        platforms,
        exclusionRules,
        rolloutPercent,
      ];
}
