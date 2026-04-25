import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/feature_flag.dart';

part 'feature_flag_state.dart';

class FeatureFlagCubit extends Cubit<FeatureFlagState> {
  FeatureFlagCubit() : super(const FeatureFlagState());

  Future<void> init() async {
    // Set isLoading: true synchronously before any await so that SplashScreen's
    // BlocConsumer sees isLoading: true as its initial state and does not
    // navigate away prematurely on the appVersion emission below.
    emit(state.copyWith(isLoading: true));

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      // copyWith without isLoading preserves the isLoading: true set above.
      if (!isClosed) emit(state.copyWith(appVersion: packageInfo.version));
    } catch (e) {
      debugPrint('[FeatureFlagCubit] PackageInfo failed: $e');
    }

    try {
      await Future.wait([fetchFlags(), _fetchUserCountry()]);
    } catch (e) {
      debugPrint('[FeatureFlagCubit] Parallel init failed: $e');
      if (!isClosed) emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> _fetchUserCountry() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final data = await Supabase.instance.client
          .from('user_profile')
          .select('country')
          .eq('id', userId)
          .maybeSingle();
      final country = data?['country'] as String?;
      if (country != null && !isClosed) {
        emit(state.copyWith(userCountry: country.toUpperCase()));
      }
    } catch (e) {
      debugPrint('[FeatureFlagCubit] _fetchUserCountry failed: $e');
    }
  }

  Future<void> fetchFlags() async {
    emit(state.copyWith(isLoading: true));
    try {
      final data =
          await Supabase.instance.client.from('feature_flags').select();

      final flags =
          (data as List).map((json) => FeatureFlag.fromMap(json)).toList();
      emit(state.copyWith(flags: flags, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  bool isEnabled(String key, {bool defaultValue = false}) {
    final flag = state.flags.firstWhere(
      (f) => f.key == key,
      orElse: () => FeatureFlag(
        key: '',
        isEnabled: defaultValue,
        platforms: const [],
        exclusionRules: const {},
        rolloutPercent: 0,
      ),
    );

    if (flag.key.isEmpty) return defaultValue;
    if (!flag.isEnabled) return false;

    // 1. Platform Check
    final currentPlatform = _getCurrentPlatform();
    if (!flag.platforms.contains(currentPlatform) &&
        !flag.platforms.contains('all')) {
      return false;
    }

    // 2. Exclusion Rules (Deny List)
    final user = Supabase.instance.client.auth.currentUser;
    final rules = flag.exclusionRules;

    if (user != null) {
      // Email Check
      if (rules.containsKey('emails')) {
        final deniedEmails = List<String>.from(rules['emails'] ?? []);
        if (deniedEmails.contains(user.email)) return false;
      }

      // User ID Check
      if (rules.containsKey('user_ids')) {
        final deniedIds = List<String>.from(rules['user_ids'] ?? []);
        if (deniedIds.contains(user.id)) return false;
      }
    }

    // Version Check
    if (rules.containsKey('versions')) {
      final vRules = rules['versions'] as Map<String, dynamic>;
      final currentVersion = state.appVersion;

      if (vRules.containsKey('min')) {
        if (_compareVersions(currentVersion, vRules['min']) < 0) return false;
      }
      if (vRules.containsKey('max')) {
        if (_compareVersions(currentVersion, vRules['max']) > 0) return false;
      }
    }

    // 3. Region Check
    if (flag.allowedRegions.isNotEmpty) {
      final country = state.userCountry;
      // If user's country is unknown, deny by default for region-restricted flags.
      if (country == null || !flag.allowedRegions.contains(country)) return false;
    }

    // 4. Rollout Check (Deterministic based on User ID)
    if (flag.rolloutPercent < 100) {
      if (user == null) return false;
      final bucket = _getUserBucket(user.id);
      if (bucket > flag.rolloutPercent) return false;
    }

    return true;
  }

  String _getCurrentPlatform() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  int _getUserBucket(String userId) {
    // Simple deterministic hash to get 0-100
    int hash = 0;
    for (int i = 0; i < userId.length; i++) {
      hash = userId.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return (hash.abs() % 100) + 1;
  }

  // Safely parse a single semver part, stripping build-number suffixes.
  // e.g. "0+15" → 0,  "3" → 3,  null/malformed → 0.
  int _parsePart(String part) => int.tryParse(part.split('+').first) ?? 0;

  int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map(_parsePart).toList();
    final parts2 = v2.split('.').map(_parsePart).toList();

    for (int i = 0; i < 3; i++) {
      final a = i < parts1.length ? parts1[i] : 0;
      final b = i < parts2.length ? parts2[i] : 0;
      if (a > b) return 1;
      if (a < b) return -1;
    }
    return 0;
  }
}
