import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:lynk_x/core/utils/embedding_manager.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  // Initialize HydratedStorage for persistent state (Web only for PWA)
  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: HydratedStorageDirectory.web,
  );

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
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
    final url = supabaseUrl.isNotEmpty ? supabaseUrl : 'https://placeholder.supabase.co';
    final key = supabaseAnonKey.isNotEmpty ? supabaseAnonKey : 'placeholder_publishable_key';
    await Supabase.initialize(url: url, publishableKey: key);
    
    // Initialize the client-side embedding worker manager
    EmbeddingManager.instance.init();
  } catch (e) {
    debugPrint('[Main] Supabase initialization failed: $e');
  }

  if (sentryDsn.isNotEmpty) {
    try {
      await SentryFlutter.init(
        (options) {
          options.dsn = sentryDsn;
          options.environment =
              const bool.fromEnvironment('dart.vm.product') ? 'production' : 'debug';
          options.tracesSampleRate = 0.1;
          options.attachScreenshot = true;
          options.screenshotQuality = SentryScreenshotQuality.low;
        },
        appRunner: () => runApp(const LynkXAppWrapper()),
      );
    } catch (e) {
      debugPrint('[Main] Sentry initialization failed: $e');
      runApp(const LynkXAppWrapper());
    }
  } else {
    runApp(const LynkXAppWrapper());
  }
}
