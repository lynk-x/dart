part of 'system_config_cubit.dart';

class SystemConfigState {
  /// Keyed by config key. Each entry carries the raw `value` string and the
  /// `data_type` enum that tells the accessors how to coerce it.
  final Map<String, SystemConfigEntry> entries;
  final bool isLoading;
  final String? error;

  const SystemConfigState({
    this.entries = const {},
    this.isLoading = false,
    this.error,
  });

  /// Returns the raw value as a string regardless of [SystemConfigEntry.dataType].
  /// Falls back to [defaultValue] when the key is absent.
  String getString(String key, {String defaultValue = ''}) {
    return entries[key]?.value ?? defaultValue;
  }

  /// Parses the entry as an int when `data_type` is `'number'`. For mismatched
  /// types or missing keys, returns [defaultValue]. Callers that care about
  /// the distinction should check `entries[key]?.dataType` directly.
  int getInt(String key, {int defaultValue = 0}) {
    final entry = entries[key];
    if (entry == null) return defaultValue;
    if (entry.dataType != 'number' && entry.dataType != 'string') {
      return defaultValue;
    }
    return int.tryParse(entry.value) ?? defaultValue;
  }

  /// Parses as a double when `data_type` is `'number'`.
  double getDouble(String key, {double defaultValue = 0.0}) {
    final entry = entries[key];
    if (entry == null) return defaultValue;
    if (entry.dataType != 'number' && entry.dataType != 'string') {
      return defaultValue;
    }
    return double.tryParse(entry.value) ?? defaultValue;
  }

  /// Parses as a bool when `data_type` is `'boolean'`. Accepts the canonical
  /// Postgres boolean string forms (`true|false|t|f|1|0`).
  bool getBool(String key, {bool defaultValue = false}) {
    final entry = entries[key];
    if (entry == null) return defaultValue;
    final v = entry.value.toLowerCase();
    if (v == 'true' || v == 't' || v == '1') return true;
    if (v == 'false' || v == 'f' || v == '0') return false;
    return defaultValue;
  }

  /// Parses the value as JSON when `data_type` is `'json'`. Returns null on
  /// parse failure or type mismatch — callers must handle null explicitly.
  dynamic getJson(String key) {
    final entry = entries[key];
    if (entry == null || entry.dataType != 'json') return null;
    try {
      return jsonDecode(entry.value);
    } catch (_) {
      return null;
    }
  }

  SystemConfigState copyWith({
    Map<String, SystemConfigEntry>? entries,
    bool? isLoading,
    String? error,
  }) {
    return SystemConfigState(
      entries: entries ?? this.entries,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}
