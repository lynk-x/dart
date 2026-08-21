// PWA Background Audio & Media Session Helper for Lynk-X
// Manages HTML5 audio DOM node, OS MediaSession metadata/controls,
// Screen WakeLock API, Web Audio AnalyserNode, local microphone capture, and page visibility re-hydration.

window.lynkAudioStreamHelper = {
  audioElement: null,
  wakeLock: null,
  audioContext: null,
  analyserNode: null,
  analyserDataArray: null,
  localAudioStream: null,

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
    }
    this.audioElement = el;
    return el;
  },

  async startLocalMicrophone() {
    try {
      if (this.localAudioStream) {
        this.stopLocalMicrophone();
      }
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        }
      });
      this.localAudioStream = stream;
      this.setupAudioAnalyser(stream);
      return true;
    } catch (e) {
      console.warn('[AudioStreamHelper] getUserMedia mic permission denied or failed:', e);
      return false;
    }
  },

  stopLocalMicrophone() {
    if (this.localAudioStream) {
      try {
        const tracks = this.localAudioStream.getTracks();
        for (let i = 0; i < tracks.length; i++) {
          tracks[i].stop();
        }
      } catch (_) {}
      this.localAudioStream = null;
    }
    this.stopAudioAnalyser();
  },

  bindRemoteStream(stream) {
    const el = this.getOrCreateAudioElement();
    el.srcObject = stream;
    el.play().catch(e => console.warn('[AudioStreamHelper] Auto-play prevented:', e));
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
    }
  },

  setupMediaSession(title, artist, artworkUrl) {
    this.getOrCreateAudioElement();

    if ('mediaSession' in navigator) {
      navigator.mediaSession.metadata = new MediaMetadata({
        title: title || 'Lynk-X Live Audio Stream',
        artist: artist || 'Lynk-X Event Community',
        album: 'Lynk-X Audio Streams',
        artwork: [
          { src: artworkUrl || 'icons/Icon-maskable-512.png', sizes: '512x512', type: 'image/png' },
          { src: 'assets/images/lynk-x_combined-logo.png', sizes: '512x512', type: 'image/png' },
          { src: 'icons/Icon-512.png', sizes: '512x512', type: 'image/png' }
        ]
      });

      navigator.mediaSession.setActionHandler('play', () => {
        if (this.audioElement) this.audioElement.play();
      });

      navigator.mediaSession.setActionHandler('pause', () => {
        if (this.audioElement) this.audioElement.pause();
      });
    }
  },

  async requestWakeLock() {
    try {
      if ('wakeLock' in navigator && !this.wakeLock) {
        this.wakeLock = await navigator.wakeLock.request('screen');
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
      }
    } catch (e) {
      console.warn('[WakeLock] Release failed:', e);
    }
  },

  clearMediaSession() {
    this.stopLocalMicrophone();
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
      if (document.visibilityState === 'visible') {
        if (this.wakeLock) {
          this.requestWakeLock();
        }
        if (onForegroundCallback) {
          onForegroundCallback();
        }
      }
    });
  }
};
