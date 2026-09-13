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
    '**/*.{js,mjs,wasm,html,css,png,svg,webp,json,woff2,otf,ttf,ico}',
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
  // so users get the latest code without needing to close all tabs. This
  // makes the new SW take control of already-open tabs right away — but the
  // tab itself decides when to actually reload to run the new code (see
  // web/index.html's controllerchange/visibilitychange handling), rather than
  // reloading the instant control changes and disrupting an in-progress
  // session.
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
    // Serve cached fonts instantly, update in the background. cacheableResponse
    // guards against caching a transient failure (e.g. a 4xx/5xx blip) and then
    // serving that same failure back for up to a year.
    {
      urlPattern: /^https:\/\/fonts\.googleapis\.com/,
      handler: 'StaleWhileRevalidate',
      options: {
        cacheName: 'google-fonts-stylesheets',
        cacheableResponse: { statuses: [0, 200] },
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
        cacheableResponse: { statuses: [0, 200] },
        expiration: {
          maxEntries: 30,
          maxAgeSeconds: 60 * 60 * 24 * 365, // 1 year
        },
      },
    },

    // ── Embedding model (R2-hosted, via cdn.lynk-x.app/models/): Cache-first ──
    // The quantized ONNX weights + tokenizer for client-side embedding
    // generation (~123MB) are immutable once uploaded — cache aggressively so
    // they're only ever downloaded once per device. Scoped to /models/ rather
    // than the whole cdn.lynk-x.app host, which also serves user media (see
    // the general-media rule below) that shouldn't get this same long-lived
    // treatment. Must come before that rule — Workbox uses the first matching
    // entry, and /models/ also matches the broader host pattern.
    {
      urlPattern: /^https:\/\/cdn\.lynk-x\.app\/models\//,
      handler: 'CacheFirst',
      options: {
        cacheName: 'embedding-model',
        cacheableResponse: { statuses: [0, 200] },
        expiration: {
          maxEntries: 10,
          maxAgeSeconds: 60 * 60 * 24 * 365, // 1 year
        },
      },
    },

    // ── User media (cdn.lynk-x.app, Cloudflare CDN + R2): Cache-first ────────
    // Forum media, profile avatars, and event posters are served from R2 via
    // Cloudflare's CDN (see ImageOptimizer, which routes them through
    // /cdn-cgi/image/... for on-the-fly resizing) — this replaced the old
    // Supabase Storage CDN, which no longer serves any of this media. Cached
    // for 30 days rather than the embedding model's 1 year, since this content
    // can change (a re-uploaded avatar, a deleted forum photo) in ways the
    // immutable model weights above never do.
    {
      urlPattern: /^https:\/\/cdn\.lynk-x\.app\//,
      handler: 'CacheFirst',
      options: {
        cacheName: 'lynkx-cdn-media',
        cacheableResponse: { statuses: [0, 200] },
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
