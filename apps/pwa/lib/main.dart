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

  await Firebase.initializeApp();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  final featureFlags = FeatureFlagCubit();
  await featureFlags.init();

  // Initialize push notifications if user is already signed in
  if (Supabase.instance.client.auth.currentUser != null) {
    await PushNotificationService.instance.init();
  }

  final crashReportingEnabled =
      sentryDsn.isNotEmpty && featureFlags.isEnabled('enable_crash_reporting');

  if (crashReportingEnabled) {
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
  } else {
    runApp(const LynkXAppWrapper());
  }
}
