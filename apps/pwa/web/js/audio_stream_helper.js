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
          channelCount: 1,
          sampleRate: 48000
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
    el.muted = false;
    el.play().catch(e => console.warn('[AudioStreamHelper] Auto-play prevented:', e));
    this.setupAudioAnalyser(stream);
  },

  setBroadcastMuted(isMuted) {
    const el = this.getOrCreateAudioElement();
    el.muted = !!isMuted;
    if (!isMuted) {
      el.play().catch(e => console.warn('[AudioStreamHelper] Play failed on unmute:', e));
      if (this.audioContext && this.audioContext.state === 'suspended') {
        this.audioContext.resume();
      }
    }
  },

  setupAudioAnalyser(stream) {
    try {
      this.stopAudioAnalyser();
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx || !stream) return;

      this.audioContext = new AudioCtx();
      const source = this.audioContext.createMediaStreamSource(stream);

      // 1. High-Pass Filter (85Hz) — Removes low frequency HVAC/fan rumble & desk thumps
      const highPassFilter = this.audioContext.createBiquadFilter();
      highPassFilter.type = 'highpass';
      highPassFilter.frequency.value = 85;

      // 2. Vocal Presence EQ Filter (3kHz Peaking) — Boosts vocal clarity and speech pickup
      const presenceEq = this.audioContext.createBiquadFilter();
      presenceEq.type = 'peaking';
      presenceEq.frequency.value = 3000;
      presenceEq.Q.value = 1.0;
      presenceEq.gain.value = 3.0; // +3dB boost for voice clarity

      // 3. Dynamics Compressor Node — Smooths voice dynamics and prevents clipping
      const compressorNode = this.audioContext.createDynamicsCompressor();
      compressorNode.threshold.value = -24;
      compressorNode.knee.value = 30;
      compressorNode.ratio.value = 12;
      compressorNode.attack.value = 0.003;
      compressorNode.release.value = 0.25;

      this.analyserNode = this.audioContext.createAnalyser();
      this.analyserNode.fftSize = 64;

      // Connect DSP chain: Source -> HighPass -> Presence EQ -> Compressor -> Analyser
      source.connect(highPassFilter);
      highPassFilter.connect(presenceEq);
      presenceEq.connect(compressorNode);
      compressorNode.connect(this.analyserNode);

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

window.lynkVideoStreamHelper = {
  videoStream: null,
  videoElement: null,
  isMicMuted: false,
  isCameraDisabled: false,

  async startVideoStream(elementId, isFrontCamera = true) {
    try {
      if (this.videoStream) {
        this.stopVideoStream();
      }

      const constraints = {
        video: { facingMode: isFrontCamera ? 'user' : 'environment' },
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          channelCount: 1,
          sampleRate: 48000
        }
      };

      const stream = await navigator.mediaDevices.getUserMedia(constraints);
      this.videoStream = stream;

      // Re-apply mic muted state if mic was muted before camera switch
      if (this.isMicMuted) {
        this.toggleMicEnabled(false);
      }
      // Re-apply camera disabled state if camera was off before camera switch
      if (this.isCameraDisabled) {
        this.toggleCameraEnabled(false);
      }

      let el = document.getElementById(elementId);
      if (el) {
        el.srcObject = stream;
        el.style.transform = isFrontCamera ? 'scaleX(-1)' : 'none';
        el.play().catch(e => console.warn('[VideoStreamHelper] video play failed:', e));
        this.videoElement = el;
      }

      if (window.lynkAudioStreamHelper) {
        window.lynkAudioStreamHelper.setupAudioAnalyser(stream);
      }

      return true;
    } catch (e) {
      console.warn('[VideoStreamHelper] getUserMedia video stream failed:', e);
      return false;
    }
  },

  setCameraMirror(isMirrored) {
    if (this.videoElement) {
      this.videoElement.style.transform = isMirrored ? 'scaleX(-1)' : 'none';
    }
  },

  toggleCameraEnabled(enabled) {
    this.isCameraDisabled = !enabled;
    if (!this.videoStream) return;
    const videoTracks = this.videoStream.getVideoTracks();
    for (let i = 0; i < videoTracks.length; i++) {
      videoTracks[i].enabled = !!enabled;
    }
    if (enabled && this.videoElement) {
      if (this.videoElement.srcObject !== this.videoStream) {
        this.videoElement.srcObject = this.videoStream;
      }
      this.videoElement.play().catch(e => console.warn('[VideoStreamHelper] video play failed:', e));
    }
  },

  toggleMicEnabled(enabled) {
    this.isMicMuted = !enabled;
    if (!this.videoStream) return;
    const audioTracks = this.videoStream.getAudioTracks();
    for (let i = 0; i < audioTracks.length; i++) {
      audioTracks[i].enabled = !!enabled;
    }
  },

  async requestPictureInPicture(elementId) {
    try {
      const el = document.getElementById(elementId) || this.videoElement;
      if (el && document.pictureInPictureEnabled) {
        if (document.pictureInPictureElement) {
          await document.exitPictureInPicture();
        } else {
          await el.requestPictureInPicture();
        }
        return true;
      }
    } catch (e) {
      console.warn('[VideoStreamHelper] requestPictureInPicture failed:', e);
    }
    return false;
  },

  async startScreenShare(elementId) {
    try {
      if (!navigator.mediaDevices || !navigator.mediaDevices.getDisplayMedia) {
        console.warn('[VideoStreamHelper] getDisplayMedia not supported');
        return false;
      }
      const displayStream = await navigator.mediaDevices.getDisplayMedia({
        video: { cursor: 'always' },
        audio: false
      });

      let el = document.getElementById(elementId) || this.videoElement;
      if (el) {
        el.srcObject = displayStream;
        el.style.transform = 'none';
        el.play().catch(e => console.warn('[VideoStreamHelper] screen share play failed:', e));
      }

      displayStream.getVideoTracks()[0].onended = () => {
        if (this.videoStream && el) {
          el.srcObject = this.videoStream;
          if (this.isFrontCamera) {
            el.style.transform = 'scaleX(-1)';
          }
        }
        window.dispatchEvent(new CustomEvent('lynkScreenShareEnded'));
      };

      return true;
    } catch (e) {
      console.warn('[VideoStreamHelper] getDisplayMedia error:', e);
      return false;
    }
  },

  stopVideoStream() {
    if (this.videoStream) {
      try {
        const tracks = this.videoStream.getTracks();
        for (let i = 0; i < tracks.length; i++) {
          tracks[i].stop();
        }
      } catch (_) {}
      this.videoStream = null;
    }
    if (window.lynkAudioStreamHelper) {
      window.lynkAudioStreamHelper.stopAudioAnalyser();
    }
  }
};
