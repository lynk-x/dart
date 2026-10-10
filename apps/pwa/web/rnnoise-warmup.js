// Service-worker add-on (loaded via importScripts from the Workbox-generated service-worker.js,
// see workbox-config.js): downloads the RNNoise assets from our CDN at install time so forum
// calls can use neural noise suppression offline, without waiting for the first call.
//
// Deliberately NOT a Workbox precache entry: a precache URL that fails to fetch (file not yet
// uploaded, CORS not configured) fails the whole service worker install and takes the app's
// offline support with it. Here every failure is swallowed — the runtime CacheFirst rule in
// workbox-config.js (same cache name) still fills the cache on the first real call.
//
// Keep the version/paths in sync with mic_processor.js (RNNOISE_VERSION) and the upload path on cdn.lynk-x.app/models/rnnoise/<version>/.

(function () {
  var CACHE_NAME = 'rnnoise'; // must match the 'rnnoise' runtimeCaching rule in workbox-config.js
  var BASE = (self.LYNK_RNNOISE_BASE || 'https://cdn.lynk-x.app/models/rnnoise/0.4.1/').replace(/\/?$/, '/');
  var FILES = ['workletProcessor.js', 'rnnoise_simd.wasm', 'rnnoise.wasm'];

  function warm() {
    return caches.open(CACHE_NAME).then(function (cache) {
      return Promise.all(FILES.map(function (file) {
        var url = BASE + file;
        return cache.match(url).then(function (hit) {
          if (hit) return;
          return cache.add(url); // CORS fetch; rejects (and caches nothing) on non-2xx
        }).catch(function () {});
      }));
    }).catch(function () {});
  }

  // install: first visit. activate: retries anything missing on later SW updates.
  self.addEventListener('install', function (event) { event.waitUntil(warm()); });
  self.addEventListener('activate', function (event) { event.waitUntil(warm()); });
})();
