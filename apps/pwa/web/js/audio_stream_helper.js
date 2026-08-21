// PWA Background Audio & Media Session Helper for Lynk-X
// Manages HTML5 audio DOM node, OS MediaSession metadata/controls,
// Screen WakeLock API, Web Audio AnalyserNode, and page visibility re-hydration.

window.lynkAudioStreamHelper = {
  audioElement: null,
  wakeLock: null,
  audioContext: null,
  analyserNode: null,
  analyserDataArray: null,

  getOrCreateAudioElement() {
    if (this.audioElement) return this.audioElement;
    let el = document.getElementById('lynk_live_audio_node');
    if (!el) {
      el = document.createElement('audio');
      el.id = 'lynk_live_audio_node';
      el.autoplay = true;
      el.style.display = 'none';
      el.setAttribute('playsinline', 'true');
      document.body.appendChild(el);
      console.log('[AudioStreamHelper] Created hidden DOM audio element: #lynk_live_audio_node');
    }
    this.audioElement = el;
    return el;
  },

  bindRemoteStream(stream) {
    console.log('[AudioStreamHelper] Binding remote audio stream to DOM node:', stream);
    const el = this.getOrCreateAudioElement();
    el.srcObject = stream;
    el.play().then(() => {
      console.log('[AudioStreamHelper] Remote stream playback started successfully.');
    }).catch(e => console.warn('[AudioStreamHelper] Auto-play prevented:', e));
    this.setupAudioAnalyser(stream);
  },

  setupAudioAnalyser(stream) {
    try {
      this.stopAudioAnalyser();
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx || !stream) return;

      this.audioContext = new AudioCtx();
      const source = this.audioContext.createMediaStreamSource(stream);
      this.analyserNode = this.audioContext.createAnalyser();
      this.analyserNode.fftSize = 64;
      source.connect(this.analyserNode);

      const bufferLength = this.analyserNode.frequencyBinCount;
      this.analyserDataArray = new Uint8Array(bufferLength);
      console.log('[AudioStreamHelper] Web Audio AnalyserNode initialized for audio level telemetry.');
    } catch (e) {
      console.warn('[AudioStreamHelper] Analyser setup failed:', e);
    }
  },

  getAudioLevel() {
    if (!this.analyserNode || !this.analyserDataArray) return 0.0;
    this.analyserNode.getByteFrequencyData(this.analyserDataArray);
    let sum = 0;
    for (let i = 0; i < this.analyserDataArray.length; i++) {
      sum += this.analyserDataArray[i];
    }
    const average = sum / this.analyserDataArray.length;
    const level = Math.min(1.0, average / 128.0);
    return level;
  },

  stopAudioAnalyser() {
    if (this.audioContext) {
      try {
        this.audioContext.close();
      } catch (_) {}
      this.audioContext = null;
      this.analyserNode = null;
      this.analyserDataArray = null;
      console.log('[AudioStreamHelper] Audio Analyser stopped.');
    }
  },

  setupMediaSession(title, artist, artworkUrl) {
    console.log('[AudioStreamHelper] Setting up OS Media Session:', { title, artist, artworkUrl });
    this.getOrCreateAudioElement();

    if ('mediaSession' in navigator) {
      navigator.mediaSession.metadata = new MediaMetadata({
        title: title || 'Lynk-X Live Audio Stream',
        artist: artist || 'Lynk-X Event Community',
        album: 'Lynk-X Audio Streams',
        artwork: [
          { src: artworkUrl || 'icons/Icon-512.png', sizes: '512x512', type: 'image/png' }
        ]
      });

      navigator.mediaSession.setActionHandler('play', () => {
        console.log('[AudioStreamHelper] OS MediaSession action: PLAY');
        if (this.audioElement) this.audioElement.play();
      });

      navigator.mediaSession.setActionHandler('pause', () => {
        console.log('[AudioStreamHelper] OS MediaSession action: PAUSE');
        if (this.audioElement) this.audioElement.pause();
      });
    }
  },

  async requestWakeLock() {
    try {
      if ('wakeLock' in navigator && !this.wakeLock) {
        this.wakeLock = await navigator.wakeLock.request('screen');
        console.log('[AudioStreamHelper] Screen WakeLock requested and acquired.');
      }
    } catch (e) {
      console.warn('[WakeLock] Request failed:', e);
    }
  },

  async releaseWakeLock() {
    try {
      if (this.wakeLock) {
        await this.wakeLock.release();
        this.wakeLock = null;
        console.log('[AudioStreamHelper] Screen WakeLock released.');
      }
    } catch (e) {
      console.warn('[WakeLock] Release failed:', e);
    }
  },

  clearMediaSession() {
    console.log('[AudioStreamHelper] Clearing OS Media Session and releasing audio resources.');
    this.releaseWakeLock();
    this.stopAudioAnalyser();
    if ('mediaSession' in navigator) {
      navigator.mediaSession.metadata = null;
    }
    if (this.audioElement) {
      this.audioElement.pause();
      this.audioElement.srcObject = null;
    }
  },

  initVisibilityListener(onForegroundCallback) {
    document.addEventListener('visibilitychange', () => {
      console.log('[AudioStreamHelper] Visibility changed:', document.visibilityState);
      if (document.visibilityState === 'visible') {
        if (this.wakeLock) {
          this.requestWakeLock();
        }
        if (typeof onForegroundCallback === 'function') {
          onForegroundCallback();
        }
      }
    });
  }
};
