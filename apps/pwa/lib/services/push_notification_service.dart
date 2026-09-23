import 'dart:async';
import 'dart:js_interop';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

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

  /// Current browser/OS notification permission, without prompting. Lets a
  /// settings screen show accurate state (and explain why re-enabling
  /// requires the OS/browser settings once a user has permanently denied)
  /// instead of blindly re-calling requestPermission on every visit.
  Future<AuthorizationStatus> checkPermissionStatus() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus;
  }

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

      if (kIsWeb) {
        _setupServiceWorkerBridge();
      }
    } catch (e) {
      debugPrint('[Push] Initialization failed: $e');
    }
  }

  /// Bridges to firebase-messaging-sw.js so it can re-derive and report a
  /// new FCM token when the browser fires `pushsubscriptionchange` — an
  /// event the browser dispatches on its own initiative (e.g. a stale
  /// subscription expiring from disuse), independent of this app's own
  /// onTokenRefresh stream. Without this, a device whose token the backend
  /// already pruned (see api.prune_unregistered_device, triggered by an FCM
  /// 404/UNREGISTERED response) stays un-notifiable until the user happens
  /// to fully relaunch the app — this closes that gap for any tab left open
  /// in the background.
  ///
  /// Two-way: sends the VAPID public key the SW needs to call
  /// messaging.getToken() itself (it has no access to this app's Dart
  /// build-time constants), and listens for the SW's resulting
  /// 'fcm-token-refreshed' message to save the new token the normal way.
  void _setupServiceWorkerBridge() {
    // No re-run guard: re-assigning the same onmessage handler and
    // re-sending the same VAPID key on every init() call is harmless and
    // idempotent, and lets a transient failure here self-heal on the next
    // auth event instead of being permanently skipped for the session.
    try {
      const vapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
      if (vapidKey.isEmpty) return;

      web.window.navigator.serviceWorker.onmessage = (web.MessageEvent event) {
        final data = event.data.dartify();
        if (data is Map && data['type'] == 'fcm-token-refreshed') {
          final newToken = data['token'] as String?;
          if (newToken != null && newToken.isNotEmpty) {
            debugPrint('[Push] Service worker reported a refreshed FCM token');
            _saveTokenToSupabase(newToken);
          }
        }
      }.toJS;

      web.window.navigator.serviceWorker.ready.toDart.then((registration) {
        registration.active?.postMessage(
          {'type': 'set-vapid-key', 'key': vapidKey}.jsify(),
        );
      });
    } catch (e) {
      debugPrint('[Push] Service worker bridge setup failed: $e');
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
      await Supabase.instance.client.schema('api').rpc('register_user_device', params: {
        'p_fcm_token': token,
        'p_info': {
          'platform': kIsWeb ? 'web' : 'other',
        },
      });
    } catch (e) {
      debugPrint('[Push] Failed to save FCM token: $e');
    }
  }

  /// Remove the current device token on sign-out to prevent cross-user leakage.
  Future<void> removeToken() async {
    try {
      String? token;
      if (kIsWeb) {
        const vapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
        if (vapidKey.isNotEmpty) {
          token = await _messaging.getToken(vapidKey: vapidKey);
        }
      } else {
        token = await _messaging.getToken();
      }

      if (token != null) {
        // Scoped to the caller's own device rows server-side.
        await Supabase.instance.client
            .schema('api')
            .rpc('remove_user_device', params: {'p_fcm_token': token});
        debugPrint('[Push] FCM token removed successfully on sign-out');
      }
    } catch (e) {
      debugPrint('[Push] Failed to remove FCM token: $e');
    }
  }

  void dispose() {
    _foregroundSub?.cancel();
    _openedSub?.cancel();
  }
}
