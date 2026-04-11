import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Top-level handler for background messages (required by firebase_messaging).
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Background messages are shown automatically by the system tray.
}

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  /// Callback invoked when a user taps a notification.
  /// Receives the `action_url` or route path from the notification data.
  void Function(String route)? onNotificationTap;

  static const _androidChannel = AndroidNotificationChannel(
    'lynkx_high',
    'Lynk-X Notifications',
    description: 'Primary notification channel for Lynk-X',
    importance: Importance.high,
  );

  Future<void> init() async {
    // Request permission
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[Push] Permission denied');
      return;
    }

    // Set up background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // Set up local notifications for foreground display
    await _initLocalNotifications();

    // Listen to foreground messages
    _foregroundSub = FirebaseMessaging.onMessage.listen(_handleForeground);

    // Listen to notification taps (app opened from background)
    _openedSub =
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Check if app was opened from a terminated state notification
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    // Register FCM token
    await _registerToken();

    // Listen for token refreshes
    _messaging.onTokenRefresh.listen((newToken) {
      _saveTokenToSupabase(newToken);
    });
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const darwinInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && onNotificationTap != null) {
          onNotificationTap!(payload);
        }
      },
    );

    // Create Android notification channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  void _handleForeground(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          icon: '@mipmap/launcher_icon',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data['action_url'] as String? ?? '/notifications',
    );
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
        // For web, pass VAPID key via dart-define
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
            'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
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

  /// Remove the current device token on sign-out.
  Future<void> removeToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await Supabase.instance.client
            .from('user_devices')
            .delete()
            .eq('fcm_token', token);
      }
    } catch (e) {
      debugPrint('[Push] Failed to remove token: $e');
    }
  }

  void dispose() {
    _foregroundSub?.cancel();
    _openedSub?.cancel();
  }
}
