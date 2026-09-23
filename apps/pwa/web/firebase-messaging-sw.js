/**
 * Firebase Messaging Service Worker
 *
 * Required for Web Push Notifications to work when the Lynk-X PWA tab is
 * backgrounded or closed. Without this file, `firebase_messaging` can obtain
 * a VAPID token but the browser has no service worker to deliver the push
 * payload to.
 *
 * This file lives in `web/` and is copied into `build/web/` by Flutter's
 * build process. Workbox's `globIgnores` excludes it from precaching since
 * the main service-worker.js loads it via `importScripts`.
 *
 * The Firebase SDK versions below must be kept in sync with the versions used
 * by `firebase_core` and `firebase_messaging` in pubspec.yaml.
 */

// Firebase App + Messaging SDKs (compat versions for SW context)
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

// Firebase config is injected at build time via environment variables.
// For the service worker context we need minimal config — just enough for
// messaging to initialise. The API key and project ID are public values
// (they are embedded in the client bundle anyway).
//
// If FIREBASE_CONFIG is not available, the SW will still register but
// background notifications will silently fail. This is acceptable for local
// dev where Firebase is not configured.
try {
  // Attempt to read config from a global set by the build pipeline.
  // Fallback: messaging won't work in background, but the SW won't crash.
  const firebaseConfig = {
    apiKey: 'AIzaSyDju1jIcIjZMvW31gxMlaMkYVxxrhftQFY',
    projectId: 'lynk-x-firebase',
    messagingSenderId: '632799565510',
    appId: '1:632799565510:web:78327f319b4f3be791e9c7',
  };

  // Only initialise if we have a real config
  if (firebaseConfig.apiKey) {
    firebase.initializeApp(firebaseConfig);
    const messaging = firebase.messaging();

    // Handle background messages (tab is not focused or closed)
    // Note: FCM SDK automatically displays a native browser notification if payload.notification is present.
    // Calling self.registration.showNotification when payload.notification exists results in duplicate popups.
    messaging.onBackgroundMessage((payload) => {
      if (payload.notification) {
        // FCM automatically handles native notification display for payload.notification
        return;
      }

      const notificationTitle = payload.data?.title || 'Lynk-X';
      const notificationOptions = {
        body: payload.data?.body || '',
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        data: payload.data,
        // Use the action_url from the payload so tapping the notification
        // navigates to the correct route (e.g. /forum/abc, /tickets).
        tag: payload.data?.action_url || payload.data?.click_action || 'default',
      };

      return self.registration.showNotification(notificationTitle, notificationOptions);
    });
  }
} catch (e) {
  console.warn('[firebase-messaging-sw] Firebase initialisation skipped:', e);
}

// The app sends its VAPID public key here shortly after init() succeeds
// (see push_notification_service.dart) — messaging.getToken() requires it,
// but it's a Dart build-time constant (--dart-define, see build.sh) not
// available to this plain, unprocessed JS file. A VAPID *public* key is
// non-secret by design (the browser transmits it as part of every push
// subscription anyway), so caching it here is no different from the rest of
// this file's already-hardcoded, non-secret Firebase config.
let cachedVapidKey = null;
self.addEventListener('message', (event) => {
  if (event.data?.type === 'set-vapid-key' && typeof event.data.key === 'string') {
    cachedVapidKey = event.data.key;
  }
});

// The browser fires this when it invalidates/rotates a push subscription on
// its own initiative (not via the app's own onTokenRefresh flow) — e.g. the
// subscription simply expired from disuse. This is a real, observed failure
// mode: a previously-working device stops receiving push because the old
// FCM token was pruned server-side (see api.prune_unregistered_device) after
// a 404/UNREGISTERED response, and nothing re-registers the new one until
// the user happens to relaunch the app. This SW-level handler closes that
// gap for the case where a tab is still open (even backgrounded) — it can't
// itself call the authenticated register_user_device RPC (no Supabase
// session in the SW context), so it re-derives the new FCM token and hands
// it to any open app tab via postMessage, which forwards to
// PushNotificationService's already-authenticated save path
// (see app.dart's navigator.serviceWorker.onmessage listener).
self.addEventListener('pushsubscriptionchange', (event) => {
  event.waitUntil(
    (async () => {
      try {
        if (typeof firebase === 'undefined' || !firebase.apps?.length) return;
        if (!cachedVapidKey) {
          console.warn('[firebase-messaging-sw] pushsubscriptionchange fired but no VAPID key cached yet — cannot re-derive token.');
          return;
        }
        const messaging = firebase.messaging();
        const newToken = await messaging.getToken({ vapidKey: cachedVapidKey });
        if (!newToken) return;

        const windowClients = await clients.matchAll({ type: 'window', includeUncontrolled: true });
        for (const client of windowClients) {
          client.postMessage({ type: 'fcm-token-refreshed', token: newToken });
        }
      } catch (e) {
        console.warn('[firebase-messaging-sw] pushsubscriptionchange handling failed:', e);
      }
    })()
  );
});

// Handle notification click — open or focus the PWA tab
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const targetUrl = event.notification.data?.action_url || '/';
  const urlToOpen = new URL(targetUrl, self.location.origin).href;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      // If the PWA is already open, focus it and navigate
      for (const client of windowClients) {
        if (client.url === urlToOpen && 'focus' in client) {
          return client.focus();
        }
      }
      // Otherwise, open a new window/tab
      if (clients.openWindow) {
        return clients.openWindow(urlToOpen);
      }
    })
  );
});
