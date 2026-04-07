part of 'system_config_cubit.dart';

class SystemConfigState {
  final Map<String, String> configs;
  final bool isLoading;
  final String? error;

  const SystemConfigState({
    this.configs = const {},
    this.isLoading = false,
    this.error,
  });

  String getString(String key, {String defaultValue = ''}) {
    return configs[key] ?? defaultValue;
  }

  int getInt(String key, {int defaultValue = 0}) {
    final value = configs[key];
    if (value == null) return defaultValue;
    return int.tryParse(value) ?? defaultValue;
  }

  SystemConfigState copyWith({
    Map<String, String>? configs,
    bool? isLoading,
    String? error,
  }) {
    return SystemConfigState(
      configs: configs ?? this.configs,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}
