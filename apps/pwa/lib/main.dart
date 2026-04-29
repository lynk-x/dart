import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // Firebase web requires explicit options (apiKey, projectId, etc.) which
  // aren't configured — skip it on web to avoid the null check crash.
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[Main] Firebase initialization skipped/failed: $e');
    }
  }

  try {
    if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    } else {
      debugPrint('[Main] Supabase credentials missing. App may be degraded.');
    }
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
