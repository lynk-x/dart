// PWA Video Broadcast Helper for Lynk-X
// Camera + microphone capture for live video streams, Cloudflare Calls publish/listen peer
// connections, device switching, and picture-in-picture. Split out of audio_stream_helper.js;
// it only talks to window.lynkAudioStreamHelper at call time (level meter), so load order between
// the two files doesn't matter.

window.lynkVideoStreamHelper = {
  videoStream: null,
  _micProcessing: null,
  videoElement: null,
  isMicMuted: false,
  isCameraDisabled: false,
  audioSender: null,
  videoSender: null,

  // Replaces the raw mic track inside [stream] with the RNNoise-processed one, so the
  // camera call publishes the same cleaned audio as a mic-only call.
  async _swapInProcessedMic(stream) {
    const rawTracks = stream.getAudioTracks();
    if (rawTracks.length === 0) return;
    // Build the new chain BEFORE tearing down the old one: the old track may still be
    // attached to the RTP sender, and stopping it first would silence the call until the
    // caller gets the replacement published.
    const previous = this._micProcessing;
    const wrapper = new MediaStream(rawTracks);
    const processing = await window.lynkMicProcessor.process(wrapper);
    this._micProcessing = processing;
    // Swap whenever the processor gave back something other than the stream we handed it: the
    // processed graph output, or (on fallback) a fresh capture opened with browser suppression on.
    // Only when it returned our own stream untouched do the original tracks stay in place.
    if (processing.stream !== wrapper) {
      rawTracks.forEach((t) => stream.removeTrack(t));
      processing.stream.getAudioTracks().forEach((t) => stream.addTrack(t));
    }
    if (previous) previous.dispose();
  },

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
        audio: window.lynkMicProcessor.audioConstraints()
      };

      const stream = await navigator.mediaDevices.getUserMedia(constraints);
      await this._swapInProcessedMic(stream);
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
        window.lynkAudioStreamHelper.setupAudioAnalyser(stream, 'local');
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

  // Re-triggers playback on [elementId]'s <video> element without
  // touching srcObject — browsers commonly freeze a live MediaStream's
  // rendered frame when its element is detached and reattached elsewhere
  // in the DOM (e.g. Flutter's HtmlElementView remounting the same
  // platform-view element into a different parent on a layout switch).
  // Call this after such a remount. play() on an already-playing element
  // is a spec-safe no-op, so this doesn't gate on el.paused — a stalled
  // decoder can freeze the frame without that flag ever flipping true.
  resumeVideoPlayback(elementId) {
    const el = document.getElementById(elementId);
    if (!el || !el.srcObject) return;
    el.play().catch(e => console.warn('[VideoStreamHelper] resumeVideoPlayback failed:', e));
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

  // Mutes/unmutes via replaceTrack() on the published sender rather than
  // stopping the local track outright — stopping it (the previous
  // behavior) permanently killed the Cloudflare publish, since a freshly
  // re-acquired track on unmute was added to this.videoStream but never
  // reattached to the already-negotiated audioSender. See
  // lynkAudioStreamHelper.toggleMicEnabled for the full rationale (same
  // fix, mirrored here for video calls' audio track). Unlike that version,
  // this one still has an audioSender to target only once
  // publishCloudflareTracks() has actually run.
  async toggleMicEnabled(enabled) {
    this.isMicMuted = !enabled;
    try {
      if (!enabled) {
        if (this.audioSender) {
          await this.audioSender.replaceTrack(null);
        }
        if (window.lynkAudioStreamHelper) {
          window.lynkAudioStreamHelper.stopAudioAnalyser('local');
        }
      } else {
        // The local track set up by startVideoStream() is still live (mute
        // no longer stops it) — only (re)acquire a fresh one if it's
        // genuinely missing.
        const existing = this.videoStream && this.videoStream.getAudioTracks()[0];
        let track = existing;
        if (!track) {
          const newStream = await navigator.mediaDevices.getUserMedia({
            audio: window.lynkMicProcessor.audioConstraints()
          });
          if (this.videoStream) {
            await this._swapInProcessedMic(newStream);
            track = newStream.getAudioTracks()[0];
            if (track) this.videoStream.addTrack(track);
          } else {
            track = newStream.getAudioTracks()[0];
          }
          if (window.lynkAudioStreamHelper) {
            window.lynkAudioStreamHelper.setupAudioAnalyser(newStream, 'local');
          }
        }
        if (track && this.audioSender) {
          await this.audioSender.replaceTrack(track);
        }
      }
    } catch (e) {
      console.warn('[VideoStreamHelper] toggleMicEnabled error:', e);
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
        audio: window.lynkMicProcessor.audioConstraints({ deviceId: { exact: deviceId } })
      });
      await this._swapInProcessedMic(newStream);
      const newAudioTrack = newStream.getAudioTracks()[0];
      if (!newAudioTrack) return false;

      if (this.videoStream) {
        const oldAudioTrack = this.videoStream.getAudioTracks()[0];
        if (oldAudioTrack) {
          this.videoStream.removeTrack(oldAudioTrack);
          oldAudioTrack.stop();
        }
        this.videoStream.addTrack(newAudioTrack);
      }

      // Publish the new mic. Without this the sender keeps the old (now stopped) track and
      // listeners hear silence after a device switch. While muted the sender intentionally
      // holds null — toggleMicEnabled(true) picks the new track up from videoStream.
      if (this.audioSender && !this.isMicMuted) {
        await this.audioSender.replaceTrack(newAudioTrack);
      }

      // The level meter was built on the old stream's source node; rebuild it so the
      // speaking indicator follows the new device.
      if (window.lynkAudioStreamHelper && !this.isMicMuted) {
        window.lynkAudioStreamHelper.setupAudioAnalyser(this.videoStream || newStream, 'local');
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
  _publishReconnectAttempts: 0,
  _publishStopped: true,

  // See lynkAudioStreamHelper's identical method for the full rationale —
  // Cloudflare's own guidance is to replace the connection (a NEW session)
  // rather than ICE-restart this one, which needs a Supabase-authenticated
  // call this JS layer can't make; this only dispatches an event, the
  // actual reconnect sequence runs in ForumVideoStage (stream_stage.dart).
  async initCloudflarePeerConnection(appId, sessionId) {
    this.cfAppId = appId;
    this.cfSessionId = sessionId;
    this._publishStopped = false;
    if (this.peerConnection) {
      try { this.peerConnection.close(); } catch (_) {}
    }
    this.peerConnection = new RTCPeerConnection({
      iceServers: [{ urls: 'stun:stun.cloudflare.com:3478' }]
    });
    this.peerConnection.oniceconnectionstatechange = () => {
      const state = this.peerConnection && this.peerConnection.iceConnectionState;
      if ((state === 'failed' || state === 'disconnected') && !this._publishStopped) {
        this._schedulePublishReconnectNotice();
      }
    };
    return true;
  },

  _schedulePublishReconnectNotice() {
    if (this._publishReconnectTimer) return;
    if (this._publishReconnectAttempts >= 3) {
      console.warn('[VideoStreamHelper] Publish reconnect gave up after 3 attempts');
      window.dispatchEvent(new CustomEvent('lynkVideoPublishLost'));
      return;
    }
    const attempt = this._publishReconnectAttempts;
    this._publishReconnectAttempts++;
    const delayMs = 1000 * Math.pow(2, attempt);
    this._publishReconnectTimer = setTimeout(() => {
      this._publishReconnectTimer = null;
      if (this._publishStopped) return;
      window.dispatchEvent(new CustomEvent('lynkVideoPublishNeedsReconnect'));
    }, delayMs);
  },

  // forceReconnect: see lynkAudioStreamHelper.publishCloudflareTracks for
  // why this is needed (a failed peerConnection is still non-null, so the
  // default guard below would otherwise try to reuse a dead connection).
  //
  // trackBaseName: defaults to '' (today's single-publisher behavior,
  // producing the unchanged literal track names 'video'/'audio') —
  // multi-speaker calls pass the speaker's own user id instead, suffixed
  // below, since one Cloudflare session still needs its video and audio
  // tracks named distinctly from each other even once the session itself
  // is already scoped to one speaker. See
  // social.forum_call_participants.track_name.
  async publishCloudflareTracks(appId, sessionId, edgeFunctionUrl, authToken, forumId, forceReconnect = false, trackBaseName = '') {
    try {
      if (!this.peerConnection || forceReconnect) {
        await this.initCloudflarePeerConnection(appId, sessionId);
      }
      this._publishReconnectAttempts = 0;
      if (!this.videoStream) return false;

      const videoTrackName = trackBaseName ? `${trackBaseName}:video` : 'video';
      const audioTrackName = trackBaseName ? `${trackBaseName}:audio` : 'audio';

      const videoTrack = this.videoStream.getVideoTracks()[0];
      const audioTrack = this.videoStream.getAudioTracks()[0];

      let videoTransceiver = null;
      let audioTransceiver = null;

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
        videoTransceiver = this.peerConnection.addTransceiver(videoTrack, {
          direction: 'sendonly',
          sendEncodings: [
            { rid: 'f', maxBitrate: 2_500_000 },
            { rid: 'h', maxBitrate: 1_000_000, scaleResolutionDownBy: 2 },
            { rid: 'q', maxBitrate: 350_000, scaleResolutionDownBy: 4 }
          ]
        });
        this.videoSender = videoTransceiver.sender;
      }
      if (audioTrack) {
        audioTransceiver = this.peerConnection.addTransceiver(audioTrack, { direction: 'sendonly' });
        this.audioSender = audioTransceiver.sender;
      }

      const rawOffer = await this.peerConnection.createOffer();
      const offer = { type: rawOffer.type, sdp: window.lynkMicProcessor.tuneOpusForVoice(rawOffer.sdp) };
      await this.peerConnection.setLocalDescription(offer);

      // transceiver.mid is null until a local description has been set
      // (WebRTC spec) — addTransceiver() alone never assigns it. Reading it
      // before setLocalDescription() (as this used to) sent mid: null for
      // every track, which Cloudflare's tracks/new rejected with
      // decoding_error "Body JSON validation error: 0,1" (both array
      // indices failing the same way, since both were null for the same
      // reason). Build the tracks array here, after mid is actually set.
      const tracks = [];
      if (videoTransceiver) {
        tracks.push({
          location: 'local',
          mid: videoTransceiver.mid,
          trackName: videoTrackName
        });
      }
      if (audioTransceiver) {
        tracks.push({
          location: 'local',
          mid: audioTransceiver.mid,
          trackName: audioTrackName
        });
      }

      if (!appId || !sessionId) {
        console.warn('[VideoStreamHelper] publishCloudflareTracks: missing appId/sessionId');
        return false;
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
          // The sender's Opus encoder is configured from the REMOTE description, so the voice
          // tuning has to be applied to the answer too — tuning only our offer would be ignored.
          await this.peerConnection.setRemoteDescription(new RTCSessionDescription({
            type: data.sessionDescription.type,
            sdp: window.lynkMicProcessor.tuneOpusForVoice(data.sessionDescription.sdp)
          }));
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
    this._publishStopped = true;
    this._publishReconnectAttempts = 0;
    if (this._publishReconnectTimer) {
      clearTimeout(this._publishReconnectTimer);
      this._publishReconnectTimer = null;
    }
    if (this.peerConnection) {
      try { this.peerConnection.close(); } catch (_) {}
      this.peerConnection = null;
    }
    this.audioSender = null;
    this.videoSender = null;
    if (this.videoStream) {
      try {
        const tracks = this.videoStream.getTracks();
        for (let i = 0; i < tracks.length; i++) {
          tracks[i].stop();
        }
      } catch (_) {}
      this.videoStream = null;
    }
    if (this._micProcessing) {
      this._micProcessing.dispose();
      this._micProcessing = null;
    }
    if (window.lynkAudioStreamHelper) {
      window.lynkAudioStreamHelper.stopAudioAnalyser('local');
    }
  },

  listenerPeerConnection: null,
  listenerElement: null,
  cfListenerSessionId: null,
  _listenerReconnectAttempts: 0,
  _listenerReconnectTimer: null,
  _listenerParams: null,
  _listenerStopped: false,
  _videoStallWatchdogTimer: null,
  _lastInboundVideoBytes: 0,
  _videoStallStrikes: 0,
  _videoListenerStartedAt: 0,

  // mid -> participant userId, mirrors
  // lynkAudioStreamHelper._midToParticipantId — see that field's comment
  // for the full rationale (ontrack only ever gets a bare transceiver.mid,
  // not participant identity).
  _videoMidToParticipantId: {},
  // participant userId -> the pre-registered Flutter platform-view
  // element id it's currently bound to (one of a small fixed pool of slot
  // elements — Dart registers these once via registerViewFactory at
  // startup, since Flutter web view factories are meant to be registered
  // upfront, not dynamically per-userId at runtime; userIds aren't known
  // ahead of time but the speaker cap is, so slots are allocated/reused
  // instead).
  _participantIdToSlotElementId: {},

  initCloudflareVideoListenerConnection(elementId) {
    this._stopInboundVideoWatchdog();
    if (this.listenerPeerConnection) {
      try { this.listenerPeerConnection.close(); } catch (_) {}
    }
    this._videoMidToParticipantId = {};
    this.listenerElement = document.getElementById(elementId) || null;
    this.listenerPeerConnection = new RTCPeerConnection({
      iceServers: [{ urls: 'stun:stun.cloudflare.com:3478' }]
    });
    this.listenerPeerConnection.ontrack = (event) => {
      if (!event.streams || !event.streams[0]) return;
      const mid = event.transceiver && event.transceiver.mid;
      const participantId = mid != null ? this._videoMidToParticipantId[mid] : null;
      if (participantId && participantId !== 'host') {
        const slotElementId = this._participantIdToSlotElementId[participantId];
        const slotEl = slotElementId ? document.getElementById(slotElementId) : null;
        if (slotEl) {
          slotEl.srcObject = event.streams[0];
          slotEl.muted = true; // video grid tiles are silent — audio comes from the separate per-participant <audio> element
          slotEl.style.objectFit = 'cover';
          slotEl.play().catch(e => console.warn('[VideoStreamHelper] participant video play failed:', e));
        }
        return;
      }
      // Single-speaker path (today's host-only call) — unchanged.
      if (this.listenerElement) {
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
    this._stopInboundVideoWatchdog();
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
    console.log(`[VideoStreamHelper] Listener connection ${this.listenerPeerConnection && this.listenerPeerConnection.iceConnectionState}, retrying in ${delayMs}ms (attempt ${attempt + 1}/3)`);
    window.dispatchEvent(new CustomEvent('lynkVideoListenerReconnecting'));

    this._listenerReconnectTimer = setTimeout(async () => {
      this._listenerReconnectTimer = null;
      if (this._listenerStopped || !this._listenerParams) return;
      const p = this._listenerParams;
      await this.joinAsVideoListener(p.elementId, p.edgeFunctionUrl, p.authToken, p.forumId, p.remoteSessionId, p.remoteTrackName);
    }, delayMs);
  },

  // Inbound video stall watchdog: detects when WebRTC claims the connection
  // is 'connected' or 'completed', but inbound video bytes have completely frozen
  // (e.g. mobile radio handoff, edge routing stall, or frozen hardware decoder).
  _startInboundVideoWatchdog() {
    this._stopInboundVideoWatchdog();
    this._lastInboundVideoBytes = 0;
    this._videoStallStrikes = 0;
    this._videoListenerStartedAt = performance.now();

    const WARMUP_MS = 4000;
    const MAX_STRIKES = 4; // 4 consecutive seconds with 0 new video bytes received while connected

    this._videoStallWatchdogTimer = setInterval(async () => {
      if (this._listenerStopped || !this.listenerPeerConnection) {
        this._stopInboundVideoWatchdog();
        return;
      }

      // Allow 4s warm-up for ICE negotiation and media buffers to start flowing
      if (performance.now() - this._videoListenerStartedAt < WARMUP_MS) return;

      const pc = this.listenerPeerConnection;
      const iceState = pc.iceConnectionState;

      // Only check when ICE claims the connection is alive
      if (iceState !== 'connected' && iceState !== 'completed') {
        this._videoStallStrikes = 0;
        return;
      }

      try {
        let currentBytes = 0;
        let hasInboundVideo = false;

        const stats = await pc.getStats();
        stats.forEach((report) => {
          if (report.type === 'inbound-rtp' && report.kind === 'video') {
            hasInboundVideo = true;
            if (report.bytesReceived !== undefined) {
              currentBytes += report.bytesReceived;
            }
          }
        });

        if (!hasInboundVideo) return;

        // If bytes received hasn't advanced while connected, count a strike
        if (this._lastInboundVideoBytes > 0 && currentBytes <= this._lastInboundVideoBytes) {
          this._videoStallStrikes++;
          console.warn(`[VideoStreamHelper] Inbound video stall detected (strike ${this._videoStallStrikes}/${MAX_STRIKES})`);

          if (this._videoStallStrikes >= MAX_STRIKES) {
            console.warn('[VideoStreamHelper] Inbound video stall sustained for 4s — triggering watchdog reconnect');
            this._stopInboundVideoWatchdog();
            this._scheduleListenerReconnect();
            return;
          }
        } else {
          this._videoStallStrikes = 0;
        }

        this._lastInboundVideoBytes = currentBytes;
      } catch (err) {
        console.warn('[VideoStreamHelper] Watchdog stats check error:', err);
      }
    }, 1000);
  },

  _stopInboundVideoWatchdog() {
    if (this._videoStallWatchdogTimer) {
      clearInterval(this._videoStallWatchdogTimer);
      this._videoStallWatchdogTimer = null;
    }
    this._videoStallStrikes = 0;
    this._lastInboundVideoBytes = 0;
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
          // Needed by addParticipantVideoTrack() to add further co-hosts'
          // video tracks to this same connection later.
          this.cfListenerSessionId = data.listenerSessionId;
          console.log('[VideoStreamHelper] Joined as video listener successfully');
          if (this._listenerReconnectAttempts > 0) {
            window.dispatchEvent(new CustomEvent('lynkVideoListenerReconnected'));
          }
          this._listenerReconnectAttempts = 0;
          this._startInboundVideoWatchdog();
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

  // Adds a co-host's VIDEO track to the EXISTING listener connection (does
  // not touch whatever is already flowing) — the multi-speaker counterpart
  // to joinAsVideoListener, which always creates a fresh connection and is
  // only for the first (host) track. Requires listenerPeerConnection to
  // already exist (call joinAsVideoListener first for the host's own
  // track). Binds into slotElementId, one of a small fixed pool of
  // pre-registered platform-view elements — see
  // _participantIdToSlotElementId's comment for why slots instead of per-
  // userId dynamic registration. Mirrors
  // lynkAudioStreamHelper.addParticipantTrack's two-step (server-offer,
  // client-answer) exchange exactly — see that method's comment for the
  // Cloudflare mechanics, verified against their own OpenAPI schema.
  async addParticipantVideoTrack(edgeFunctionUrl, authToken, forumId, participantUserId, slotElementId, remoteSessionId, remoteTrackName) {
    if (!this.listenerPeerConnection) {
      console.warn('[VideoStreamHelper] addParticipantVideoTrack: no existing listener connection — call joinAsVideoListener first');
      return false;
    }

    this._participantIdToSlotElementId[participantUserId] = slotElementId;

    try {
      const res = await fetch(`${edgeFunctionUrl}/cloudflare-calls-session`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({
          action: 'add_remote_track',
          forumId: forumId,
          listenerSessionId: this.cfListenerSessionId,
          remoteSessionId: remoteSessionId,
          remoteTrackName: remoteTrackName
        })
      });

      if (!res.ok) {
        console.warn('[VideoStreamHelper] add_remote_track request failed:', res.status);
        return false;
      }

      const data = await res.json();
      if (!data.sessionDescription || !data.sessionDescription.sdp) {
        console.warn('[VideoStreamHelper] add_remote_track: no offer in response');
        return false;
      }

      const newTrackInfo = (data.tracks || []).find(t => t.trackName === remoteTrackName);
      if (newTrackInfo && newTrackInfo.mid != null) {
        this._videoMidToParticipantId[newTrackInfo.mid] = participantUserId;
      }

      await this.listenerPeerConnection.setRemoteDescription(new RTCSessionDescription(data.sessionDescription));
      const answer = await this.listenerPeerConnection.createAnswer();
      await this.listenerPeerConnection.setLocalDescription(answer);

      const renegRes = await fetch(`${edgeFunctionUrl}/cloudflare-calls-session`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({
          action: 'renegotiate_listener',
          forumId: forumId,
          listenerSessionId: this.cfListenerSessionId,
          sessionDescription: {
            type: 'answer',
            sdp: answer.sdp
          }
        })
      });

      if (!renegRes.ok) {
        console.warn('[VideoStreamHelper] renegotiate_listener request failed:', renegRes.status);
        return false;
      }

      console.log('[VideoStreamHelper] Added participant video track successfully:', participantUserId);
      return true;
    } catch (e) {
      console.warn('[VideoStreamHelper] addParticipantVideoTrack error:', e);
      return false;
    }
  },

  // Frees a participant's slot element and mid mapping — does NOT
  // renegotiate or notify Cloudflare, same reasoning as
  // lynkAudioStreamHelper.removeParticipantTrack.
  removeParticipantVideoTrack(participantUserId) {
    const slotElementId = this._participantIdToSlotElementId[participantUserId];
    if (slotElementId) {
      const slotEl = document.getElementById(slotElementId);
      if (slotEl) {
        slotEl.pause();
        slotEl.srcObject = null;
      }
      delete this._participantIdToSlotElementId[participantUserId];
    }
    for (const mid of Object.keys(this._videoMidToParticipantId)) {
      if (this._videoMidToParticipantId[mid] === participantUserId) {
        delete this._videoMidToParticipantId[mid];
      }
    }
  },

  stopListeningVideo() {
    this._stopInboundVideoWatchdog();
    this._listenerStopped = true;
    this._listenerParams = null;
    this._listenerReconnectAttempts = 0;
    this.cfListenerSessionId = null;
    this._videoMidToParticipantId = {};
    for (const participantId of Object.keys(this._participantIdToSlotElementId)) {
      this.removeParticipantVideoTrack(participantId);
    }
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
