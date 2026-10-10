// Mic processing for forum calls: RNNoise (neural noise suppression) + light dynamics.
// Owns the capture constraints and the Web Audio graph whose output is the track
// actually published to Cloudflare, so audio_stream_helper.js never publishes a raw mic.
//
// Chain: mic (browser echo cancel + auto gain, browser noise suppression OFF)
//   -> high-pass -> RNNoise -> compressor -> limiter -> MediaStreamDestination
//
// Browser noise suppression is disabled only while RNNoise is in use — running both
// degrades the voice. Any failure falls back to the raw mic with browser suppression
// turned back on, so a call never starts without noise handling or fails outright.
//
// Kill switch: window.lynkMicConfig.neuralNoiseSuppression = false, or
// localStorage 'lynk_neural_ns' = '0'. window.lynkMicConfig.rnnoiseBaseUrl overrides the CDN path
// (e.g. a local dev server).
// If the CDN is unreachable (offline, first visit) the load times out and the call uses the
// browser's own noise suppression; once fetched, Workbox serves the assets from cache.

window.lynkMicConfig = window.lynkMicConfig || { neuralNoiseSuppression: true };

window.lynkMicProcessor = (function () {
  const WORKLET_ID = '@sapphi-red/web-noise-suppressor/rnnoise';
  const SAMPLE_RATE = 48000; // RNNoise assumes 48 kHz
  const LOAD_TIMEOUT_MS = 5000; // a CDN problem delays mic start by at most this long
  // Hosted on our CDN (not bundled in the PWA build): version-pinned and immutable, so
  // bump RNNOISE_VERSION together with a new upload to cdn.lynk-x.app/models/rnnoise/<version>/.
  const RNNOISE_VERSION = '0.4.1';
  const BASE = (window.lynkMicConfig.rnnoiseBaseUrl
    || 'https://cdn.lynk-x.app/models/rnnoise/' + RNNOISE_VERSION + '/').replace(/\/?$/, '/');

  let wasmPromise = null;
  let lastStatus = { mode: 'none' };

  function readOverride() {
    try {
      return localStorage.getItem('lynk_neural_ns');
    } catch (_) {
      return null;
    }
  }

  function supportsWasmSimd() {
    return WebAssembly.validate(new Uint8Array([
      0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 96, 0, 1, 123, 3, 2, 1, 0, 10, 10, 1, 8, 0, 65, 0, 253, 15, 253, 98, 11
    ]));
  }

  function loadWasm() {
    if (!wasmPromise) {
      const url = BASE + (supportsWasmSimd() ? 'rnnoise_simd.wasm' : 'rnnoise.wasm');
      wasmPromise = fetch(url).then((r) => {
        if (!r.ok) throw new Error('rnnoise wasm HTTP ' + r.status);
        return r.arrayBuffer();
      }).catch((e) => {
        wasmPromise = null; // allow a retry on the next call
        throw e;
      });
    }
    return wasmPromise;
  }

  function withTimeout(promise, ms) {
    return Promise.race([
      promise,
      new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), ms)),
    ]);
  }

  const api = {
    // How the most recent process() call set up the mic: { mode: 'neural' | 'browser' |
    // 'browser_fallback' | 'none', reason?, setupMs? }. Read by Dart (mic_status_reporter.dart).
    getLastStatus() {
      return JSON.stringify(lastStatus);
    },

    isNeuralEnabled() {
      if (readOverride() === '0') return false;
      if (readOverride() === '1') return true;
      return window.lynkMicConfig.neuralNoiseSuppression !== false
        && typeof AudioWorkletNode !== 'undefined'
        && typeof WebAssembly !== 'undefined';
    },

    // Browser auto gain stays on by default. It overlaps with our compressor, and how well the
    // two cooperate varies by phone — set lynkMicConfig.autoGainControl = false (or
    // localStorage 'lynk_agc' = '0') to let the compressor + limiter do all the levelling and
    // compare on a real device without a code change.
    isAutoGainEnabled() {
      try {
        const v = localStorage.getItem('lynk_agc');
        if (v === '0') return false;
        if (v === '1') return true;
      } catch (_) {}
      return window.lynkMicConfig.autoGainControl !== false;
    },

    // Capture constraints for every mic acquisition. Echo cancellation must stay with
    // the browser (it only works at capture); noise suppression moves to RNNoise.
    audioConstraints(extra) {
      return Object.assign({
        echoCancellation: true,
        noiseSuppression: !api.isNeuralEnabled(),
        autoGainControl: api.isAutoGainEnabled(),
        channelCount: 1,
        sampleRate: SAMPLE_RATE,
      }, extra || {});
    },

    // Rewrites the Opus fmtp line(s) of an SDP offer for speech over weak mobile networks:
    //  - useinbandfec=1  forward error correction, so a lost packet is concealed instead of dropped
    //  - usedtx=1        no packets during silence (RNNoise leaves pauses near-silent) — saves data
    //  - stereo=0 / sprop-stereo=0  the mic is mono; never spend bits on a second channel
    //  - maxaveragebitrate=32000    plenty for full-band mono voice, ~4x lighter than the 128 kbps
    //                               some browsers default to for "music-like" content
    // Other parameters already in the line (e.g. minptime) are kept. Returns the SDP unchanged
    // if it has no Opus payload.
    tuneOpusForVoice(sdp) {
      const wanted = {
        useinbandfec: '1',
        usedtx: '1',
        stereo: '0',
        'sprop-stereo': '0',
        maxaveragebitrate: '32000',
      };
      const lines = sdp.split('\r\n');
      const payloadTypes = [];
      for (const line of lines) {
        const m = /^a=rtpmap:(\d+) opus\/48000/i.exec(line);
        if (m) payloadTypes.push(m[1]);
      }
      if (payloadTypes.length === 0) return sdp;

      const out = [];
      for (const line of lines) {
        out.push(line);
        const rtpmap = /^a=rtpmap:(\d+) opus\/48000/i.exec(line);
        if (!rtpmap) continue;
        const pt = rtpmap[1];
        const hasFmtp = lines.some((l) => l.startsWith('a=fmtp:' + pt + ' '));
        if (!hasFmtp) {
          out.push('a=fmtp:' + pt + ' ' + Object.keys(wanted).map((k) => k + '=' + wanted[k]).join(';'));
        }
      }
      return out.map((line) => {
        const m = /^a=fmtp:(\d+) (.*)$/.exec(line);
        if (!m || payloadTypes.indexOf(m[1]) === -1) return line;
        const params = {};
        m[2].split(';').forEach((kv) => {
          const i = kv.indexOf('=');
          if (i > 0) params[kv.slice(0, i).trim()] = kv.slice(i + 1).trim();
        });
        Object.assign(params, wanted);
        return 'a=fmtp:' + m[1] + ' ' + Object.keys(params).map((k) => k + '=' + params[k]).join(';');
      }).join('\r\n');
    },

    // Takes a raw mic MediaStream, returns { stream, dispose, processed }.
    // dispose() tears down the graph and stops the raw tracks; it is safe to call twice.
    async process(rawStream) {
      const startedAt = performance.now();
      const fallback = async (reason) => {
        console.warn('[MicProcessor] falling back to browser noise suppression:', reason);
        lastStatus = { mode: 'browser_fallback', reason: String(reason), setupMs: Math.round(performance.now() - startedAt) };
        // The raw track was captured with noiseSuppression off — turn it back on.
        for (const track of rawStream.getAudioTracks()) {
          try { await track.applyConstraints({ noiseSuppression: true }); } catch (_) {}
        }
        return {
          stream: rawStream,
          processed: false,
          dispose() {
            rawStream.getTracks().forEach((t) => t.stop());
          },
        };
      };

      if (!api.isNeuralEnabled()) {
        lastStatus = { mode: 'browser' };
        return { stream: rawStream, processed: false, dispose() { rawStream.getTracks().forEach((t) => t.stop()); } };
      }

      let ctx = null;
      try {
        const AudioCtx = window.AudioContext || window.webkitAudioContext;
        ctx = new AudioCtx({ sampleRate: SAMPLE_RATE, latencyHint: 'interactive' });
        // Safari can ignore the requested rate; RNNoise at any other rate sounds wrong.
        if (ctx.sampleRate !== SAMPLE_RATE) {
          throw new Error('AudioContext sampleRate ' + ctx.sampleRate);
        }

        const [wasmBinary] = await withTimeout(Promise.all([
          loadWasm(),
          ctx.audioWorklet.addModule(BASE + 'workletProcessor.js'),
        ]), LOAD_TIMEOUT_MS);

        if (ctx.state === 'suspended') await ctx.resume().catch(() => {});

        const source = ctx.createMediaStreamSource(rawStream);

        // 1. High-pass — handling thumps / rumble that confuse the denoiser.
        const highPass = ctx.createBiquadFilter();
        highPass.type = 'highpass';
        highPass.frequency.value = 95;

        // 2. RNNoise.
        const rnnoise = new AudioWorkletNode(ctx, WORKLET_ID, {
          channelCount: 1,
          channelCountMode: 'explicit',
          outputChannelCount: [1],
          processorOptions: { maxChannels: 1, wasmBinary },
        });

        // 3. Gentle compressor — evens out near/far speakers without pumping.
        const compressor = ctx.createDynamicsCompressor();
        compressor.threshold.value = -24;
        compressor.knee.value = 12;
        compressor.ratio.value = 3;
        compressor.attack.value = 0.01;
        compressor.release.value = 0.2;

        // 4. Limiter — only there to catch shouting/clipping.
        const limiter = ctx.createDynamicsCompressor();
        limiter.threshold.value = -3;
        limiter.knee.value = 0;
        limiter.ratio.value = 20;
        limiter.attack.value = 0.001;
        limiter.release.value = 0.05;

        const destination = ctx.createMediaStreamDestination();

        source.connect(highPass);
        highPass.connect(rnnoise);
        rnnoise.connect(compressor);
        compressor.connect(limiter);
        limiter.connect(destination);

        lastStatus = { mode: 'neural', setupMs: Math.round(performance.now() - startedAt) };
        let disposed = false;
        return {
          stream: destination.stream,
          processed: true,
          dispose() {
            if (disposed) return;
            disposed = true;
            try { rnnoise.port.postMessage('destroy'); } catch (_) {}
            try { source.disconnect(); } catch (_) {}
            try { rnnoise.disconnect(); } catch (_) {}
            destination.stream.getTracks().forEach((t) => t.stop());
            rawStream.getTracks().forEach((t) => t.stop());
            ctx.close().catch(() => {});
          },
        };
      } catch (e) {
        if (ctx) { try { ctx.close(); } catch (_) {} }
        return fallback(e && e.message ? e.message : e);
      }
    },
  };

  return api;
})();
