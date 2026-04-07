import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'system_config_state.dart';

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
          .select('key, value')
          .eq('is_active', true);

      final Map<String, String> configs = {};
      for (final item in (data as List)) {
        configs[item['key'] as String] = item['value'] as String;
      }

      emit(state.copyWith(configs: configs, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }
}
