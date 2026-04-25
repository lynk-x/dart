import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:lynk_core/core.dart';
import 'app.dart';
import 'services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('[Main] Firebase initialization skipped/failed: $e');
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

  final featureFlags = FeatureFlagCubit();
  try {
    await featureFlags.init();
  } catch (e) {
    debugPrint('[Main] FeatureFlag initialization failed: $e');
  }

  // Initialize push notifications if user is already signed in and Supabase is ready
  try {
    // Check if Supabase is initialized before accessing instance
    final hasSupabase = supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
    if (hasSupabase && Supabase.instance.client.auth.currentUser != null) {
      await PushNotificationService.instance.init();
    }
  } catch (_) {}

  final crashReportingEnabled =
      sentryDsn.isNotEmpty && featureFlags.isEnabled('enable_crash_reporting');

  if (crashReportingEnabled) {
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
