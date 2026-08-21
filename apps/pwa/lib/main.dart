import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'app.dart';

/// Fallback [Storage] used when [HydratedStorage.build] fails (e.g.
/// IndexedDB unavailable in private/incognito mode, or blocked by a
/// privacy extension). Keeps the app bootable without persisted state.
class _InMemoryStorage implements Storage {
  final Map<String, dynamic> _data = {};

  @override
  dynamic read(String key) => _data[key];

  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> close() async {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  // Initialize HydratedStorage for persistent state (Web only for PWA)
  try {
    if (kIsWeb) {
      HydratedBloc.storage = await HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory.web,
      );
    } else {
      HydratedBloc.storage = _InMemoryStorage();
    }
  } catch (_) {
    HydratedBloc.storage = _InMemoryStorage();
  }

  // Lock orientation to portrait
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (e) {
    debugPrint('[Main] setPreferredOrientations failed: $e');
  }

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  try {
    if (kIsWeb) {
      // Provide explicit options for the web client to match the service worker
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyDju1jIcIjZMvW31gxMlaMkYVxxrhftQFY',
          appId: '1:632799565510:web:78327f319b4f3be791e9c7',
          messagingSenderId: '632799565510',
          projectId: 'lynk-x-firebase',
        ),
      );
    } else {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('[Main] Firebase initialization skipped/failed: $e');
  }

  try {
    final url = supabaseUrl.isNotEmpty
        ? supabaseUrl
        : 'https://placeholder.supabase.co';
    final key = supabaseAnonKey.isNotEmpty
        ? supabaseAnonKey
        : 'placeholder_publishable_key';
    await Supabase.initialize(url: url, publishableKey: key);
  } catch (e) {
    debugPrint('[Main] Supabase initialization failed: $e');
  }

  if (sentryDsn.isNotEmpty) {
    try {
      if (kIsWeb) {
        await Sentry.init(
          (options) {
            options.dsn = sentryDsn;
            options.environment = const bool.fromEnvironment('dart.vm.product')
                ? 'production'
                : 'debug';
            options.tracesSampleRate = 0.1;
          },
          appRunner: () => runApp(const LynkXAppWrapper()),
        );
      } else {
        await SentryFlutter.init(
          (options) {
            options.dsn = sentryDsn;
            options.environment = const bool.fromEnvironment('dart.vm.product')
                ? 'production'
                : 'debug';
            options.tracesSampleRate = 0.1;
            options.attachScreenshot = true;
            options.screenshotQuality = SentryScreenshotQuality.low;
          },
          appRunner: () => runApp(const LynkXAppWrapper()),
        );
      }
    } catch (e) {
      runApp(const LynkXAppWrapper());
    }
  } else {
    runApp(const LynkXAppWrapper());
  }
}
