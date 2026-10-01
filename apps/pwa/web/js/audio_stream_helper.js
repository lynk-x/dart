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

  listenerPeerConnection: null,
  _listenerReconnectAttempts: 0,
  _listenerReconnectTimer: null,
  _listenerParams: null,
  _listenerStopped: false,

  initCloudflareListenerConnection() {
    if (this.listenerPeerConnection) {
      try { this.listenerPeerConnection.close(); } catch (_) {}
    }
    this.listenerPeerConnection = new RTCPeerConnection({
      iceServers: [{ urls: 'stun:stun.cloudflare.com:3478' }]
    });
    this.listenerPeerConnection.ontrack = (event) => {
      if (event.streams && event.streams[0]) {
        this.bindRemoteStream(event.streams[0]);
      }
    };
    // ICE state is the signal a listener's connection has actually died
    // (vs. just being momentarily slow to connect) — 'failed' means ICE
    // gave up finding a working candidate pair, 'disconnected' means one
    // was lost and may or may not recover on its own. Both warrant a retry
    // since neither self-heals reliably on mobile networks (handoffs,
    // brief signal loss) without renegotiating a fresh session.
    this.listenerPeerConnection.oniceconnectionstatechange = () => {
      const state = this.listenerPeerConnection && this.listenerPeerConnection.iceConnectionState;
      if (state === 'failed' || state === 'disconnected') {
        this._scheduleListenerReconnect();
      }
    };
    return true;
  },

  // Bounded retry: 3 attempts with short backoff (1s/2s/4s) covers a brief
  // network blip without leaving a listener silently retrying forever
  // against a call that's genuinely ended or a connection that's
  // permanently gone. A failed ICE connection generally can't be revived
  // by renegotiating the same Cloudflare session, so each attempt redoes
  // the full join (fresh listener session + fresh offer) via joinAsListener.
  _scheduleListenerReconnect() {
    if (this._listenerStopped || !this._listenerParams) return;
    if (this._listenerReconnectTimer) return;
    if (this._listenerReconnectAttempts >= 3) {
      console.warn('[AudioStreamHelper] Listener reconnect gave up after 3 attempts');
      window.dispatchEvent(new CustomEvent('lynkAudioListenerLost'));
      return;
    }

    const attempt = this._listenerReconnectAttempts;
    this._listenerReconnectAttempts++;
    const delayMs = 1000 * Math.pow(2, attempt);
    console.log(`[AudioStreamHelper] Listener connection ${this.listenerPeerConnection.iceConnectionState}, retrying in ${delayMs}ms (attempt ${attempt + 1}/3)`);

    this._listenerReconnectTimer = setTimeout(async () => {
      this._listenerReconnectTimer = null;
      if (this._listenerStopped || !this._listenerParams) return;
      const p = this._listenerParams;
      await this.joinAsListener(p.edgeFunctionUrl, p.authToken, p.forumId, p.remoteSessionId, p.remoteTrackName);
    }, delayMs);
  },

  // Joins an already-live host session in one Edge Function round-trip
  // (session creation + remote track pull combined server-side, via the
  // join_as_listener action) instead of two — halves both the auth/DB
  // membership-check work and the network latency a listener pays on join,
  // which matters most exactly when it's most likely to happen: many
  // listeners joining within the same few seconds of a popular call starting.
  async joinAsListener(edgeFunctionUrl, authToken, forumId, remoteSessionId, remoteTrackName) {
    this._listenerStopped = false;
    this._listenerParams = { edgeFunctionUrl, authToken, forumId, remoteSessionId, remoteTrackName };

    try {
      this.initCloudflareListenerConnection();
      this.listenerPeerConnection.addTransceiver('audio', { direction: 'recvonly' });

      const offer = await this.listenerPeerConnection.createOffer();
      await this.listenerPeerConnection.setLocalDescription(offer);

      if (remoteSessionId.startsWith('mock_')) {
        console.log('[AudioStreamHelper] Mock Cloudflare remote track pull simulated');
        this._listenerReconnectAttempts = 0;
        return true;
      }

      const res = await fetch(`${edgeFunctionUrl}/cloudflare-calls-session`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({
          action: 'join_as_listener',
          forumId: forumId,
          remoteSessionId: remoteSessionId,
          remoteTrackName: remoteTrackName,
          sessionDescription: {
            type: 'offer',
            sdp: offer.sdp
          }
        })
      });

      if (res.ok) {
        const data = await res.json();
        if (data.sessionDescription && data.sessionDescription.sdp) {
          await this.listenerPeerConnection.setRemoteDescription(new RTCSessionDescription(data.sessionDescription));
          console.log('[AudioStreamHelper] Joined as listener successfully');
          this._listenerReconnectAttempts = 0;
          return true;
        }
      } else {
        console.warn('[AudioStreamHelper] join_as_listener request failed:', res.status);
      }
    } catch (e) {
      console.warn('[AudioStreamHelper] joinAsListener error:', e);
    }
    return false;
  },

  // Tears down the listener-side peer connection and detaches the remote
  // stream from the audio element. Does NOT touch localAudioStream (the
  // listener's own mic, if they're also speaking) — that's stopLocalMicrophone's job.
  stopListening() {
    this._listenerStopped = true;
    this._listenerParams = null;
    this._listenerReconnectAttempts = 0;
    if (this._listenerReconnectTimer) {
      clearTimeout(this._listenerReconnectTimer);
      this._listenerReconnectTimer = null;
    }
    if (this.listenerPeerConnection) {
      try { this.listenerPeerConnection.close(); } catch (_) {}
      this.listenerPeerConnection = null;
    }
    if (this.audioElement) {
      this.audioElement.pause();
      this.audioElement.srcObject = null;
    }
  },

  _lastListenerAudioStatsTimestamp: 0,

  // Receive-side quality for a listener's own connection — audio has no
  // simulcast layers to report (one mono voice stream, not tiered), but
  // packetLossPercent/jitter/rttMs are still the real signal for "is this
  // call breaking up for me specifically," independent of how clean the
  // host's own upload is.
  async getListenerAudioTelemetryStats() {
    let rttMs = 0;
    let packetLossPercent = '0.0';
    let jitterMs = 0;

    if (!this.listenerPeerConnection) {
      return JSON.stringify({ rttMs, packetLossPercent, jitterMs, connected: false });
    }

    try {
      const stats = await this.listenerPeerConnection.getStats();
      stats.forEach(report => {
        if (report.type === 'inbound-rtp' && report.kind === 'audio') {
          if (report.jitter !== undefined) jitterMs = Math.round(report.jitter * 1000);
          if (report.packetsLost !== undefined && report.packetsReceived !== undefined) {
            const total = report.packetsLost + report.packetsReceived;
            if (total > 0) {
              packetLossPercent = ((report.packetsLost / total) * 100).toFixed(1);
            }
          }
        }
        if (report.type === 'candidate-pair' && report.state === 'succeeded' && report.currentRoundTripTime) {
          rttMs = Math.round(report.currentRoundTripTime * 1000);
        }
      });
    } catch (e) {
      console.warn('[AudioStreamHelper] getListenerAudioTelemetryStats error:', e);
    }

    return JSON.stringify({ rttMs, packetLossPercent, jitterMs, connected: true });
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
    if (this.audioContext && this.audioContext.state === 'suspended') {
      this.audioContext.resume().catch(() => {});
    }
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
  },

  successAudioBuffer: null,
  errorAudioBuffer: null,
  isAudioPreloaded: false,

  async preloadScanAudioFiles() {
    if (this.isAudioPreloaded) return;
    try {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx) return;
      if (!this.sharedAudioContext) {
        this.sharedAudioContext = new AudioCtx();
      }
      const ctx = this.sharedAudioContext;

      const loadSound = async (pathCandidates) => {
        for (const url of pathCandidates) {
          try {
            const resp = await fetch(url);
            if (resp.ok) {
              const arrayBuf = await resp.arrayBuffer();
              return await ctx.decodeAudioData(arrayBuf);
            }
          } catch (_) {}
        }
        return null;
      };

      const [successBuf, errorBuf] = await Promise.all([
        loadSound([
          'assets/assets/audio/success.mp3',
          'assets/audio/success.mp3',
          '/assets/assets/audio/success.mp3'
        ]),
        loadSound([
          'assets/assets/audio/error.mp3',
          'assets/audio/error.mp3',
          '/assets/assets/audio/error.mp3'
        ])
      ]);

      if (successBuf) this.successAudioBuffer = successBuf;
      if (errorBuf) this.errorAudioBuffer = errorBuf;
      this.isAudioPreloaded = true;
    } catch (e) {
      console.warn('[AudioStreamHelper] preloadScanAudioFiles failed:', e);
    }
  },

  playFeedbackTone(isSuccess) {
    try {
      if (!this.isAudioPreloaded) {
        this.preloadScanAudioFiles();
      }

      const buffer = isSuccess ? this.successAudioBuffer : this.errorAudioBuffer;
      if (!buffer) {
        // Fallback: create dynamic audio element if buffers aren't loaded yet
        const soundPath = isSuccess ? 'assets/assets/audio/success.mp3' : 'assets/assets/audio/error.mp3';
        const audio = new Audio(soundPath);
        audio.play().catch(() => {});
        return;
      }

      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx) return;
      
      if (!this.sharedAudioContext || this.sharedAudioContext.state === 'closed') {
        this.sharedAudioContext = new AudioCtx();
      }
      const ctx = this.sharedAudioContext;
      if (ctx.state === 'suspended') {
        ctx.resume();
      }

      const source = ctx.createBufferSource();
      source.buffer = buffer;
      source.connect(ctx.destination);
      source.start(0);
    } catch (e) {
      console.warn('[AudioStreamHelper] playFeedbackTone failed:', e);
    }
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
        video: {
          facingMode: isFrontCamera ? 'user' : 'environment',
          width: { ideal: 1280, max: 1920 },
          height: { ideal: 720, max: 1080 },
          frameRate: { ideal: 30, max: 30 }
        },
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

      const attachVideo = (retries = 10) => {
        let el = document.getElementById(elementId);
        if (el) {
          el.muted = true;
          el.defaultMuted = true;
          el.srcObject = stream;
          el.style.objectFit = 'cover';
          el.style.transform = isFrontCamera ? 'scaleX(-1)' : 'none';
          el.play().catch(e => console.warn('[VideoStreamHelper] video play failed:', e));
          this.videoElement = el;
        } else if (retries > 0) {
          setTimeout(() => attachVideo(retries - 1), 100);
        } else {
          console.warn('[VideoStreamHelper] target video element not found:', elementId);
        }
      };
      attachVideo();

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

  async toggleCameraEnabled(enabled) {
    this.isCameraDisabled = !enabled;
    if (!enabled) {
      // Stop video tracks to ensure hardware camera LED indicator turns off completely
      if (this.videoStream) {
        const videoTracks = this.videoStream.getVideoTracks();
        for (let i = 0; i < videoTracks.length; i++) {
          videoTracks[i].stop();
          this.videoStream.removeTrack(videoTracks[i]);
        }
      }
    } else {
      // Re-acquire camera video track when toggled back ON
      try {
        const constraints = {
          video: {
            facingMode: this.isFrontCamera ? 'user' : 'environment',
            width: { ideal: 1280, max: 1920 },
            height: { ideal: 720, max: 1080 },
            frameRate: { ideal: 30, max: 30 }
          }
        };
        const newStream = await navigator.mediaDevices.getUserMedia(constraints);
        const newTrack = newStream.getVideoTracks()[0];
        if (newTrack && this.videoStream) {
          this.videoStream.addTrack(newTrack);
        }
        if (this.videoElement) {
          this.videoElement.srcObject = this.videoStream;
          this.videoElement.play().catch(e => console.warn('[VideoStreamHelper] video play failed:', e));
        }
      } catch (e) {
        console.warn('[VideoStreamHelper] re-enabling camera failed:', e);
      }
    }
  },

  async toggleMicEnabled(enabled) {
    this.isMicMuted = !enabled;
    if (!enabled) {
      // Stop audio tracks to ensure OS hardware microphone indicator light turns off completely
      if (this.videoStream) {
        const audioTracks = this.videoStream.getAudioTracks();
        for (let i = 0; i < audioTracks.length; i++) {
          audioTracks[i].stop();
          this.videoStream.removeTrack(audioTracks[i]);
        }
      }
      if (window.lynkAudioStreamHelper) {
        window.lynkAudioStreamHelper.stopAudioAnalyser();
      }
    } else {
      // Re-acquire microphone audio track when unmuted
      try {
        const audioConstraints = {
          audio: {
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
            channelCount: 1,
            sampleRate: 48000
          }
        };
        const newStream = await navigator.mediaDevices.getUserMedia(audioConstraints);
        const newAudioTrack = newStream.getAudioTracks()[0];
        if (newAudioTrack && this.videoStream) {
          this.videoStream.addTrack(newAudioTrack);
        }
        if (window.lynkAudioStreamHelper) {
          window.lynkAudioStreamHelper.setupAudioAnalyser(newStream);
        }
      } catch (e) {
        console.warn('[VideoStreamHelper] re-enabling microphone failed:', e);
      }
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
      if (!navigator.mediaDevices || typeof navigator.mediaDevices.getDisplayMedia !== 'function') {
        console.warn('[VideoStreamHelper] getDisplayMedia API is not available on this mobile platform/browser environment.');
        return false;
      }

      let displayStream;
      try {
        displayStream = await navigator.mediaDevices.getDisplayMedia({
          video: true,
          audio: false
        });
      } catch (err1) {
        console.warn('[VideoStreamHelper] Primary getDisplayMedia failed, trying unconstrained fallback:', err1);
        try {
          displayStream = await navigator.mediaDevices.getDisplayMedia();
        } catch (err2) {
          console.warn('[VideoStreamHelper] Fallback getDisplayMedia also failed:', err2);
          return false;
        }
      }

      let el = document.getElementById(elementId) || this.videoElement;
      if (el) {
        el.muted = true;
        el.defaultMuted = true;
        el.srcObject = displayStream;
        el.style.objectFit = 'contain';
        el.style.transform = 'none';
        el.play().catch(e => console.warn('[VideoStreamHelper] screen share play failed:', e));
      }

      const videoTrack = displayStream.getVideoTracks()[0];
      if (videoTrack) {
        videoTrack.onended = () => {
          if (this.videoStream && el) {
            el.muted = true;
            el.defaultMuted = true;
            el.srcObject = this.videoStream;
            el.style.objectFit = 'cover';
            if (this.isFrontCamera) {
              el.style.transform = 'scaleX(-1)';
            }
          }
          window.dispatchEvent(new CustomEvent('lynkScreenShareEnded'));
        };
      }

      return true;
    } catch (e) {
      console.warn('[VideoStreamHelper] getDisplayMedia error:', e);
      return false;
    }
  },

  _deviceChangeListenerBound: false,
  _ensureDeviceChangeListener() {
    if (this._deviceChangeListenerBound) return;
    if (navigator.mediaDevices && typeof navigator.mediaDevices.addEventListener === 'function') {
      navigator.mediaDevices.addEventListener('devicechange', () => {
        window.dispatchEvent(new CustomEvent('lynkMediaDevicesChanged'));
      });
      this._deviceChangeListenerBound = true;
    }
  },

  async getAvailableDevices() {
    try {
      this._ensureDeviceChangeListener();
      if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) {
        return JSON.stringify([]);
      }
      const devices = await navigator.mediaDevices.enumerateDevices();
      const result = devices.map(d => ({
        deviceId: d.deviceId,
        kind: d.kind,
        label: d.label || (d.kind === 'videoinput' ? 'Camera (' + d.deviceId.slice(0, 5) + '...)' : d.kind === 'audiooutput' ? 'Speaker (' + d.deviceId.slice(0, 5) + '...)' : 'Microphone (' + d.deviceId.slice(0, 5) + '...)')
      }));
      return JSON.stringify(result);
    } catch (e) {
      console.warn('[VideoStreamHelper] enumerateDevices error:', e);
      return JSON.stringify([]);
    }
  },

  async switchAudioDevice(deviceId) {
    try {
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) return false;
      const newStream = await navigator.mediaDevices.getUserMedia({
        audio: { deviceId: { exact: deviceId } }
      });
      const newAudioTrack = newStream.getAudioTracks()[0];
      if (this.videoStream && newAudioTrack) {
        const oldAudioTrack = this.videoStream.getAudioTracks()[0];
        if (oldAudioTrack) {
          this.videoStream.removeTrack(oldAudioTrack);
          oldAudioTrack.stop();
        }
        this.videoStream.addTrack(newAudioTrack);
      }
      return true;
    } catch (e) {
      console.warn('[VideoStreamHelper] switchAudioDevice error:', e);
      return false;
    }
  },

  async switchCameraDevice(elementId, deviceId) {
    try {
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) return false;
      const newStream = await navigator.mediaDevices.getUserMedia({
        video: { deviceId: { exact: deviceId } },
        audio: false
      });
      const newVideoTrack = newStream.getVideoTracks()[0];
      let el = document.getElementById(elementId) || this.videoElement;
      if (this.videoStream && newVideoTrack) {
        const oldVideoTrack = this.videoStream.getVideoTracks()[0];
        if (oldVideoTrack) {
          this.videoStream.removeTrack(oldVideoTrack);
          oldVideoTrack.stop();
        }
        this.videoStream.addTrack(newVideoTrack);
        if (el) {
          el.srcObject = this.videoStream;
        }
      }
      return true;
    } catch (e) {
      console.warn('[VideoStreamHelper] switchCameraDevice error:', e);
      return false;
    }
  },

  async switchAudioOutputDevice(elementId, deviceId) {
    try {
      let el = document.getElementById(elementId) || this.videoElement;
      if (el && typeof el.setSinkId === 'function') {
        await el.setSinkId(deviceId);
        return true;
      }
      return false;
    } catch (e) {
      console.warn('[VideoStreamHelper] setSinkId error:', e);
      return false;
    }
  },

  async setStreamQuality(elementId, quality) {
    try {
      if (!this.videoStream) return false;
      const videoTrack = this.videoStream.getVideoTracks()[0];
      if (!videoTrack) return false;
      let height = 720;
      let frameRate = 30;
      if (quality.includes('1080')) {
        height = 1080;
        frameRate = 60;
      } else if (quality.includes('720')) {
        height = 720;
        frameRate = 30;
      } else if (quality.includes('480')) {
        height = 480;
        frameRate = 24;
      } else if (quality.includes('360')) {
        height = 360;
        frameRate = 15;
      }
      if (videoTrack.applyConstraints) {
        await videoTrack.applyConstraints({
          height: { ideal: height },
          frameRate: { ideal: frameRate }
        });
      }
      return true;
    } catch (e) {
      console.warn('[VideoStreamHelper] setStreamQuality error:', e);
      return false;
    }
  },

  peerConnection: null,
  cfSessionId: null,
  cfAppId: null,

  async initCloudflarePeerConnection(appId, sessionId) {
    this.cfAppId = appId;
    this.cfSessionId = sessionId;
    if (this.peerConnection) {
      try { this.peerConnection.close(); } catch (_) {}
    }
    this.peerConnection = new RTCPeerConnection({
      iceServers: [{ urls: 'stun:stun.cloudflare.com:3478' }]
    });
    return true;
  },

  async publishCloudflareTracks(appId, sessionId, edgeFunctionUrl, authToken, forumId) {
    try {
      if (!this.peerConnection) {
        await this.initCloudflarePeerConnection(appId, sessionId);
      }
      if (!this.videoStream) return false;

      const tracks = [];
      const videoTrack = this.videoStream.getVideoTracks()[0];
      const audioTrack = this.videoStream.getAudioTracks()[0];

      if (videoTrack) {
        // Simulcast: publish three independent encodings of the same track
        // instead of one. Without this every listener gets the host's full
        // resolution/bitrate regardless of their own device or network —
        // Cloudflare's SFU can only forward what was actually published, it
        // can't transcode a single stream down. The browser encodes all
        // three layers from this one getUserMedia track; Cloudflare reads
        // the rid layers out of the SDP this addTransceiver call produces
        // (no separate signaling needed) and lets each subscriber request
        // whichever rid it wants via setPreferredLayers at pull time.
        // scaleResolutionDownBy rungs (1x/2x/4x) follow the standard
        // f(ull)/h(alf)/q(uarter) simulcast naming convention.
        const transceiver = this.peerConnection.addTransceiver(videoTrack, {
          direction: 'sendonly',
          sendEncodings: [
            { rid: 'f', maxBitrate: 2_500_000 },
            { rid: 'h', maxBitrate: 1_000_000, scaleResolutionDownBy: 2 },
            { rid: 'q', maxBitrate: 350_000, scaleResolutionDownBy: 4 }
          ]
        });
        tracks.push({
          location: 'local',
          mid: transceiver.mid,
          trackName: 'video'
        });
      }
      if (audioTrack) {
        const transceiver = this.peerConnection.addTransceiver(audioTrack, { direction: 'sendonly' });
        tracks.push({
          location: 'local',
          mid: transceiver.mid,
          trackName: 'audio'
        });
      }

      const offer = await this.peerConnection.createOffer();
      await this.peerConnection.setLocalDescription(offer);

      if (!appId || !sessionId || appId === '' || sessionId.startsWith('mock_')) {
        console.log('[VideoStreamHelper] Mock Cloudflare WebRTC SDP exchange simulated');
        return true;
      }

      const res = await fetch(`${edgeFunctionUrl}/cloudflare-calls-session`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({
          action: 'publish_track',
          forumId: forumId,
          sessionId: sessionId,
          sessionDescription: {
            type: 'offer',
            sdp: offer.sdp
          },
          tracks: tracks
        })
      });

      if (res.ok) {
        const data = await res.json();
        if (data.sessionDescription && data.sessionDescription.sdp) {
          await this.peerConnection.setRemoteDescription(new RTCSessionDescription(data.sessionDescription));
          console.log('[VideoStreamHelper] Cloudflare Calls WebRTC stream published successfully');
          return true;
        }
      } else {
        console.warn('[VideoStreamHelper] publish_track request failed:', res.status);
      }
    } catch (e) {
      console.warn('[VideoStreamHelper] Cloudflare Calls publish error:', e);
    }
    return false;
  },

  lastBytesSent: 0,
  lastStatsTimestamp: 0,

  async getTelemetryStats() {
    let width = 1280;
    let height = 720;
    let fps = 30;
    let rttMs = 28;
    let bitrateMbps = '2.8';
    let packetLossPercent = '0.0';
    let codec = 'H.264 / Opus';

    if (this.videoStream) {
      const vTrack = this.videoStream.getVideoTracks()[0];
      if (vTrack && vTrack.getSettings) {
        const settings = vTrack.getSettings();
        if (settings.width) width = settings.width;
        if (settings.height) height = settings.height;
        if (settings.frameRate) fps = Math.round(settings.frameRate);
      }
    } else if (this.videoElement) {
      if (this.videoElement.videoWidth) width = this.videoElement.videoWidth;
      if (this.videoElement.videoHeight) height = this.videoElement.videoHeight;
    }

    if (this.peerConnection) {
      try {
        const stats = await this.peerConnection.getStats();
        const now = performance.now();
        stats.forEach(report => {
          if (report.type === 'outbound-rtp' && report.kind === 'video') {
            if (this.lastBytesSent > 0 && this.lastStatsTimestamp > 0) {
              const bytesDelta = report.bytesSent - this.lastBytesSent;
              const timeDeltaMs = now - this.lastStatsTimestamp;
              if (timeDeltaMs > 0) {
                const bps = (bytesDelta * 8) / (timeDeltaMs / 1000);
                bitrateMbps = (bps / 1000000).toFixed(1);
              }
            }
            this.lastBytesSent = report.bytesSent;
            this.lastStatsTimestamp = now;
            if (report.framesPerSecond) fps = Math.round(report.framesPerSecond);
          }
          if (report.type === 'candidate-pair' && report.state === 'succeeded') {
            if (report.currentRoundTripTime) {
              rttMs = Math.round(report.currentRoundTripTime * 1000);
            }
          }
          if (report.type === 'remote-inbound-rtp' && report.packetsLost !== undefined && report.packetsReceived !== undefined) {
            const total = report.packetsLost + report.packetsReceived;
            if (total > 0) {
              packetLossPercent = ((report.packetsLost / total) * 100).toFixed(1);
            }
          }
        });
      } catch (e) {
        console.warn('[VideoStreamHelper] getStats error:', e);
      }
    }

    return JSON.stringify({
      width: width,
      height: height,
      fps: fps,
      rttMs: rttMs,
      bitrateMbps: bitrateMbps,
      packetLossPercent: packetLossPercent,
      codec: codec
    });
  },

  stopVideoStream() {
    if (this.peerConnection) {
      try { this.peerConnection.close(); } catch (_) {}
      this.peerConnection = null;
    }
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
  },

  listenerPeerConnection: null,
  listenerElement: null,
  _listenerReconnectAttempts: 0,
  _listenerReconnectTimer: null,
  _listenerParams: null,
  _listenerStopped: false,

  initCloudflareVideoListenerConnection(elementId) {
    if (this.listenerPeerConnection) {
      try { this.listenerPeerConnection.close(); } catch (_) {}
    }
    this.listenerElement = document.getElementById(elementId) || null;
    this.listenerPeerConnection = new RTCPeerConnection({
      iceServers: [{ urls: 'stun:stun.cloudflare.com:3478' }]
    });
    this.listenerPeerConnection.ontrack = (event) => {
      if (event.streams && event.streams[0] && this.listenerElement) {
        this.listenerElement.srcObject = event.streams[0];
        this.listenerElement.muted = false;
        this.listenerElement.style.objectFit = 'cover';
        this.listenerElement.play().catch(e => console.warn('[VideoStreamHelper] remote video play failed:', e));
      }
    };
    // See lynkAudioStreamHelper's identical handler for the full rationale
    // (ICE failed/disconnected is the real "connection is dead" signal on
    // mobile networks; bounded retry redoes the full join since the same
    // session generally can't be renegotiated back to health).
    this.listenerPeerConnection.oniceconnectionstatechange = () => {
      const state = this.listenerPeerConnection && this.listenerPeerConnection.iceConnectionState;
      if (state === 'failed' || state === 'disconnected') {
        this._scheduleListenerReconnect();
      }
    };
    return true;
  },

  _scheduleListenerReconnect() {
    if (this._listenerStopped || !this._listenerParams) return;
    if (this._listenerReconnectTimer) return;
    if (this._listenerReconnectAttempts >= 3) {
      console.warn('[VideoStreamHelper] Listener reconnect gave up after 3 attempts');
      window.dispatchEvent(new CustomEvent('lynkVideoListenerLost'));
      return;
    }

    const attempt = this._listenerReconnectAttempts;
    this._listenerReconnectAttempts++;
    const delayMs = 1000 * Math.pow(2, attempt);
    console.log(`[VideoStreamHelper] Listener connection ${this.listenerPeerConnection.iceConnectionState}, retrying in ${delayMs}ms (attempt ${attempt + 1}/3)`);

    this._listenerReconnectTimer = setTimeout(async () => {
      this._listenerReconnectTimer = null;
      if (this._listenerStopped || !this._listenerParams) return;
      const p = this._listenerParams;
      await this.joinAsVideoListener(p.elementId, p.edgeFunctionUrl, p.authToken, p.forumId, p.remoteSessionId, p.remoteTrackName);
    }, delayMs);
  },

  // Joins an already-live host video session in one Edge Function
  // round-trip (session creation + remote track pull combined server-side)
  // instead of two — same scaling motivation as the audio listener path.
  async joinAsVideoListener(elementId, edgeFunctionUrl, authToken, forumId, remoteSessionId, remoteTrackName) {
    this._listenerStopped = false;
    this._listenerParams = { elementId, edgeFunctionUrl, authToken, forumId, remoteSessionId, remoteTrackName };

    try {
      this.initCloudflareVideoListenerConnection(elementId);
      this.listenerPeerConnection.addTransceiver('video', { direction: 'recvonly' });

      const offer = await this.listenerPeerConnection.createOffer();
      await this.listenerPeerConnection.setLocalDescription(offer);

      if (remoteSessionId.startsWith('mock_')) {
        console.log('[VideoStreamHelper] Mock Cloudflare remote video track pull simulated');
        this._listenerReconnectAttempts = 0;
        return true;
      }

      const res = await fetch(`${edgeFunctionUrl}/cloudflare-calls-session`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({
          action: 'join_as_listener',
          forumId: forumId,
          remoteSessionId: remoteSessionId,
          remoteTrackName: remoteTrackName,
          sessionDescription: {
            type: 'offer',
            sdp: offer.sdp
          }
        })
      });

      if (res.ok) {
        const data = await res.json();
        if (data.sessionDescription && data.sessionDescription.sdp) {
          await this.listenerPeerConnection.setRemoteDescription(new RTCSessionDescription(data.sessionDescription));
          console.log('[VideoStreamHelper] Joined as video listener successfully');
          this._listenerReconnectAttempts = 0;
          return true;
        }
      } else {
        console.warn('[VideoStreamHelper] join_as_listener request failed:', res.status);
      }
    } catch (e) {
      console.warn('[VideoStreamHelper] joinAsVideoListener error:', e);
    }
    return false;
  },

  stopListeningVideo() {
    this._listenerStopped = true;
    this._listenerParams = null;
    this._listenerReconnectAttempts = 0;
    if (this._listenerReconnectTimer) {
      clearTimeout(this._listenerReconnectTimer);
      this._listenerReconnectTimer = null;
    }
    if (this.listenerPeerConnection) {
      try { this.listenerPeerConnection.close(); } catch (_) {}
      this.listenerPeerConnection = null;
    }
    if (this.listenerElement) {
      this.listenerElement.pause();
      this.listenerElement.srcObject = null;
      this.listenerElement = null;
    }
  },

  _lastListenerBytesReceived: 0,
  _lastListenerStatsTimestamp: 0,

  // Receive-side counterpart to getTelemetryStats() (which only reports the
  // HOST's own outgoing connection). This is what actually tells a listener
  // whether their own link is struggling — necessary now that publishing is
  // simulcast (3 layers): Cloudflare's SFU picks which layer to forward per
  // receiver, so a listener's experienced quality can differ from the
  // host's regardless of what the host is sending. Surfaces which
  // resolution is actually arriving so the UI can show it, not just infer
  // it from the host's own stats.
  async getListenerTelemetryStats() {
    let width = 0, height = 0, fps = 0, rttMs = 0;
    let bitrateMbps = '0.0', packetLossPercent = '0.0';

    if (!this.listenerPeerConnection) {
      return JSON.stringify({ width, height, fps, rttMs, bitrateMbps, packetLossPercent, connected: false });
    }

    try {
      const stats = await this.listenerPeerConnection.getStats();
      const now = performance.now();
      stats.forEach(report => {
        if (report.type === 'inbound-rtp' && report.kind === 'video') {
          if (report.frameWidth) width = report.frameWidth;
          if (report.frameHeight) height = report.frameHeight;
          if (report.framesPerSecond) fps = Math.round(report.framesPerSecond);
          if (this._lastListenerBytesReceived > 0 && this._lastListenerStatsTimestamp > 0) {
            const bytesDelta = report.bytesReceived - this._lastListenerBytesReceived;
            const timeDeltaMs = now - this._lastListenerStatsTimestamp;
            if (timeDeltaMs > 0) {
              const bps = (bytesDelta * 8) / (timeDeltaMs / 1000);
              bitrateMbps = (bps / 1000000).toFixed(1);
            }
          }
          this._lastListenerBytesReceived = report.bytesReceived;
          this._lastListenerStatsTimestamp = now;
          if (report.packetsLost !== undefined && report.packetsReceived !== undefined) {
            const total = report.packetsLost + report.packetsReceived;
            if (total > 0) {
              packetLossPercent = ((report.packetsLost / total) * 100).toFixed(1);
            }
          }
        }
        if (report.type === 'candidate-pair' && report.state === 'succeeded' && report.currentRoundTripTime) {
          rttMs = Math.round(report.currentRoundTripTime * 1000);
        }
      });
    } catch (e) {
      console.warn('[VideoStreamHelper] getListenerTelemetryStats error:', e);
    }

    return JSON.stringify({ width, height, fps, rttMs, bitrateMbps, packetLossPercent, connected: true });
  }
};
