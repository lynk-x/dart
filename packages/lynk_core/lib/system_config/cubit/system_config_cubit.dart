import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'system_config_state.dart';

/// One row of `system_config`. `dataType` mirrors the DB enum
/// `config_data_type` (`string | boolean | number | json`) and drives
/// the typed accessors on [SystemConfigState].
class SystemConfigEntry {
  final String value;
  final String dataType;

  const SystemConfigEntry({required this.value, required this.dataType});
}

class SystemConfigCubit extends Cubit<SystemConfigState> {
  SystemConfigCubit() : super(const SystemConfigState());

  Future<void> init() async {
    await fetchConfigs();
  }

  Future<void> fetchConfigs() async {
    emit(state.copyWith(isLoading: true));
    try {
      final data = await Supabase.instance.client
          .from('system_config')
          .select('key, value, data_type')
          .eq('is_active', true);

      final Map<String, SystemConfigEntry> entries = {};
      for (final item in (data as List)) {
        final map = item as Map<String, dynamic>;
        entries[map['key'] as String] = SystemConfigEntry(
          value: map['value'] as String,
          // Defensive: legacy rows may have NULL data_type.
          dataType: (map['data_type'] as String?) ?? 'string',
        );
      }

      emit(state.copyWith(entries: entries, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }
}
