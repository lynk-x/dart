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

  Future<void> init() async {
    // Web push requires a service worker and VAPID key.
    // If not configured, we gracefully exit.
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[Push] Permission denied');
        return;
      }

      // Listen to foreground messages (Web displays these via browser UI if configured)
      _foregroundSub = FirebaseMessaging.onMessage.listen(_handleForeground);

      // Listen to notification taps
      _openedSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Register FCM token
      await _registerToken();

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
    // On Web, browsers usually handle the display if the site is open.
  }

  void _handleNotificationTap(RemoteMessage message) {
    final route =
        message.data['action_url'] as String? ?? '/notifications';
    onNotificationTap?.call(route);
  }

  Future<void> _registerToken() async {
    try {
      String? token;
      if (kIsWeb) {
        const vapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
        token = await _messaging.getToken(vapidKey: vapidKey.isNotEmpty ? vapidKey : null);
      } else {
        token = await _messaging.getToken();
      }

      if (token != null) {
        await _saveTokenToSupabase(token);
      }
    } catch (e) {
      debugPrint('[Push] Failed to get FCM token: $e');
    }
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
