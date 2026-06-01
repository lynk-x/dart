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
    messaging.onBackgroundMessage((payload) => {
      const notificationTitle = payload.notification?.title || 'Lynk-X';
      const notificationOptions = {
        body: payload.notification?.body || '',
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        data: payload.data,
        // Use the action_url from the payload so tapping the notification
        // navigates to the correct route (e.g. /forum/abc, /tickets).
        tag: payload.data?.action_url || 'default',
      };

      return self.registration.showNotification(notificationTitle, notificationOptions);
    });
  }
} catch (e) {
  console.warn('[firebase-messaging-sw] Firebase initialisation skipped:', e);
}

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
