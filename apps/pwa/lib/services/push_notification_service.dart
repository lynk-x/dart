import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// PushNotificationService for PWA.
///
/// Handles Firebase Cloud Messaging for Web Push.
/// Local notifications plugin is removed as it is mobile-only.
class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  late final _messaging = FirebaseMessaging.instance;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  /// Callback invoked when a user taps a notification.
  void Function(String route)? onNotificationTap;

  /// Callback invoked when notification permission is denied.
  /// The app can use this to show an explanatory prompt.
  void Function()? onPermissionDenied;

  Future<void> init() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[Push] Permission denied');
        onPermissionDenied?.call();
        return;
      }

      // Listen to foreground messages (Web displays these via browser UI if configured)
      _foregroundSub = FirebaseMessaging.onMessage.listen(_handleForeground);

      // Listen to notification taps
      _openedSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Register FCM token with retry
      await _registerTokenWithRetry();

      // Listen for token refreshes
      _messaging.onTokenRefresh.listen((newToken) {
        _saveTokenToSupabase(newToken);
      });
    } catch (e) {
      debugPrint('[Push] Initialization failed: $e');
    }
  }

  void _handleForeground(RemoteMessage message) {
    debugPrint('[Push] Foreground message received: ${message.notification?.title}');
  }

  void _handleNotificationTap(RemoteMessage message) {
    final route =
        message.data['action_url'] as String? ?? '/notifications';
    onNotificationTap?.call(route);
  }

  /// Attempts to register the FCM token up to [maxAttempts] times with
  /// exponential back-off. Silently gives up after exhausting retries so a
  /// temporary FCM outage doesn't surface a noisy error to the user.
  Future<void> _registerTokenWithRetry({int maxAttempts = 3}) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        String? token;
        if (kIsWeb) {
          const vapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
          if (vapidKey.isEmpty) {
            debugPrint('[Push] FIREBASE_VAPID_KEY is not set — skipping web push registration');
            return;
          }
          token = await _messaging.getToken(vapidKey: vapidKey);
        } else {
          token = await _messaging.getToken();
        }

        if (token != null) {
          await _saveTokenToSupabase(token);
          return;
        }
      } catch (e) {
        debugPrint('[Push] Token registration attempt $attempt/$maxAttempts failed: $e');
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    debugPrint('[Push] Token registration failed after $maxAttempts attempts');
  }

  Future<void> _saveTokenToSupabase(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client.from('user_devices').upsert(
        {
          'user_id': user.id,
          'fcm_token': token,
          'info': {
            'platform': kIsWeb ? 'web' : 'other',
          },
          'last_active_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'fcm_token',
      );
      debugPrint('[Push] FCM token saved');
    } catch (e) {
      debugPrint('[Push] Failed to save FCM token: $e');
    }
  }

  /// Remove the current device token on sign-out (Stub for PWA).
  Future<void> removeToken() async {
    // Web push token removal logic can be added here if needed.
  }

  void dispose() {
    _foregroundSub?.cancel();
    _openedSub?.cancel();
  }
}
