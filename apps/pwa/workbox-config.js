/**
 * Workbox Configuration for Lynk-X PWA
 *
 * Generates a production service worker that:
 *  1. Pre-caches the Flutter app shell (index.html, main.dart.js, WASM, fonts)
 *  2. Excludes all Supabase API / Realtime traffic from caching
 *  3. Merges with firebase-messaging-sw.js for background push support
 *
 * Run after `flutter build web`:
 *   npx workbox-cli generateSW workbox-config.js
 */
module.exports = {
  // ── Source & Destination ───────────────────────────────────────────────────
  globDirectory: 'build/web',
  swDest: 'build/web/service-worker.js',
  maximumFileSizeToCacheInBytes: 15 * 1024 * 1024, // 15MB (allows precaching of large Flutter Wasm/JS/CanvasKit assets)

  // ── Precache: Static app shell ─────────────────────────────────────────────
  // Glob every static asset Flutter produces. Workbox hashes each file and
  // only re-downloads files that actually changed between deploys.
  globPatterns: [
    '**/*.{js,mjs,wasm,html,css,png,svg,webp,json,woff2,ico}',
  ],

  // Exclude files that should never be pre-cached:
  //  - Source maps (large, dev-only)
  //  - The SW itself (circular)
  //  - Firebase messaging SW (loaded via importScripts, not pre-cached)
  globIgnores: [
    '**/*.map',
    'service-worker.js',
    'firebase-messaging-sw.js',
  ],

  // ── SW Behaviour ──────────────────────────────────────────────────────────
  // skipWaiting + clientsClaim = new SW activates immediately on deploy,
  // so users get the latest code without needing to close all tabs.
  skipWaiting: true,
  clientsClaim: true,

  // ── Navigation Fallback ───────────────────────────────────────────────────
  // Flutter uses client-side routing (GoRouter). Any navigation request that
  // doesn't match a cached file should fall back to index.html so the Flutter
  // router can handle the route (e.g. /forum/abc, /wallet/settings).
  navigateFallback: '/index.html',
  navigateFallbackAllowlist: [
    // Only fallback for same-origin navigation requests
    /^(?!\/__).*/,
  ],

  // ── Runtime Caching (requests NOT in the precache manifest) ────────────────
  runtimeCaching: [
    // ── Supabase API & Realtime: NEVER cache ─────────────────────────────────
    // Supabase REST, Auth, Realtime, Storage, and Edge Functions traffic must
    // always go to the network. Caching any of these would break auth token
    // refresh, Realtime WebSocket upgrades, wallet balance updates, and forum
    // presence tracking.
    {
      urlPattern: /\.supabase\.co/,
      handler: 'NetworkOnly',
    },

    // ── Google Fonts: Stale-while-revalidate ─────────────────────────────────
    // Serve cached fonts instantly, update in the background.
    {
      urlPattern: /^https:\/\/fonts\.googleapis\.com/,
      handler: 'StaleWhileRevalidate',
      options: {
        cacheName: 'google-fonts-stylesheets',
        expiration: {
          maxEntries: 10,
          maxAgeSeconds: 60 * 60 * 24 * 365, // 1 year
        },
      },
    },
    {
      urlPattern: /^https:\/\/fonts\.gstatic\.com/,
      handler: 'CacheFirst',
      options: {
        cacheName: 'google-fonts-webfonts',
        expiration: {
          maxEntries: 30,
          maxAgeSeconds: 60 * 60 * 24 * 365, // 1 year
        },
      },
    },

    // ── Supabase Storage (CDN images/videos): Cache-first ────────────────────
    // Forum media, profile avatars, event posters are served from Supabase
    // Storage CDN. Cache them aggressively to avoid re-downloading large files.
    {
      urlPattern: /\.supabase\.co\/storage\/v1\/object\/public\//,
      handler: 'CacheFirst',
      options: {
        cacheName: 'supabase-storage-cdn',
        expiration: {
          maxEntries: 200,
          maxAgeSeconds: 60 * 60 * 24 * 30, // 30 days
        },
      },
    },

    // ── Sentry SDK: Network-only (telemetry, never cache) ────────────────────
    {
      urlPattern: /\.sentry\.io/,
      handler: 'NetworkOnly',
    },

    // ── Firebase: Network-only (FCM token registration, analytics) ───────────
    {
      urlPattern: /\.googleapis\.com\/identitytoolkit/,
      handler: 'NetworkOnly',
    },
    {
      urlPattern: /fcmregistrations\.googleapis\.com/,
      handler: 'NetworkOnly',
    },
  ],
};
