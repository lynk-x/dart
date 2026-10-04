// PWA Background Audio & Media Session Helper for Lynk-X
// Manages HTML5 audio DOM node, OS MediaSession metadata/controls,
// Screen WakeLock API, Web Audio AnalyserNode, local microphone capture, and page visibility re-hydration.

window.lynkAudioStreamHelper = {
  audioElement: null,
  wakeLock: null,
  // Two independent analysers — one for this user's own mic (set up by
  // startLocalMicrophone, used by host/co-host), one for the remote
  // host's pulled stream (set up by bindRemoteStream, used by a pure
  // listener). Previously a SINGLE shared audioContext/analyserNode pair
  // was reused for both, so whichever setupAudioAnalyser() call ran most
  // recently silently tore down and replaced the other — a listener who
  // became a co-host lost the ability to visualize the host's audio
  // entirely, since only one source could ever be measured at a time.
  // getAudioLevel() below prefers the local analyser when one exists
  // (publishing is the more actionable "am I audible" signal), falling
  // back to the remote one for a pure listener.
  localAudioContext: null,
  localAnalyserNode: null,
  localAnalyserDataArray: null,
  remoteAudioContext: null,
  remoteAnalyserNode: null,
  remoteAnalyserDataArray: null,
  localAudioStream: null,

  hasLocalMicrophone() {
    return !!this.localAudioStream && this.localAudioStream.getAudioTracks().length > 0;
  },

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
      this.setupAudioAnalyser(stream, 'local');
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
    this.stopAudioAnalyser('local');
  },

  bindRemoteStream(stream) {
    const el = this.getOrCreateAudioElement();
    el.srcObject = stream;
    el.muted = false;
    el.play().catch(e => console.warn('[AudioStreamHelper] Auto-play prevented:', e));
    this.setupAudioAnalyser(stream, 'remote');
  },

  // One <audio> element per remote participant — binding every pulled
  // stream to the single shared element (bindRemoteStream, still used for
  // the single-speaker host pull) would make each new stream silently
  // replace the previous one's srcObject, so only the most recently
  // joined participant would ever actually be heard. Keyed by userId so a
  // given participant's element can be found again on participant_left
  // teardown.
  _remoteParticipantElements: {},

  bindRemoteParticipantStream(userId, stream) {
    let el = this._remoteParticipantElements[userId];
    if (!el) {
      el = document.createElement('audio');
      el.id = `lynk_live_audio_node_${userId}`;
      el.autoplay = true;
      el.style.display = 'none';
      el.setAttribute('playsinline', 'true');
      document.body.appendChild(el);
      this._remoteParticipantElements[userId] = el;
    }
    el.srcObject = stream;
    el.muted = false;
    el.play().catch(e => console.warn('[AudioStreamHelper] Participant auto-play prevented:', e));
  },

  unbindRemoteParticipantStream(userId) {
    const el = this._remoteParticipantElements[userId];
    if (!el) return;
    el.pause();
    el.srcObject = null;
    el.remove();
    delete this._remoteParticipantElements[userId];
  },

  listenerPeerConnection: null,
  cfListenerSessionId: null,
  _listenerReconnectAttempts: 0,
  _listenerReconnectTimer: null,
  _listenerParams: null,
  _listenerStopped: false,

  // ─── Host publish (audio-only calls) ───
  // This was previously entirely missing: startLocalMicrophone() only ever
  // captured the mic for local analysis (mute toggle / amplitude meter),
  // and createCloudflareSession() only created a session id — nothing ever
  // published the host's mic track into it. Listeners' joinAsListener()
  // pulled from a session no track was ever attached to, so audio calls
  // showed zero Cloudflare Analytics data (no edge-function errors, since
  // publish_track was simply never called) while livestreams — which do
  // have this publish step via lynkVideoStreamHelper — worked correctly.
  // Mirrors lynkVideoStreamHelper.publishCloudflareTracks, audio-only (no
  // simulcast — one mono voice stream has no quality tiers to publish).
  peerConnection: null,
  _publishReconnectAttempts: 0,
  _publishStopped: true,

  // Cloudflare's own docs say to replace the connection (new session) on a
  // publish failure rather than ICE-restart the same one — there is no
  // documented same-session recovery for a publisher — so detecting
  // failure here only dispatches an event; it cannot fix itself the way
  // the listener side's _scheduleListenerReconnect does. Creating a new
  // Cloudflare session, re-publishing, persisting the new session id to
  // streaming_config, and telling listeners to rejoin all require a
  // Supabase-authenticated call this JS layer can't make on its own — that
  // sequence lives in ForumAudioStreamCubit, driven by this event.
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

  // Bounded — same 3-attempt shape as the listener side, but this only
  // notifies Dart once per attempt (with backoff) rather than retrying
  // itself; the Dart-driven reconnect sequence calls
  // initCloudflarePeerConnection() again on success, which resets
  // _publishReconnectAttempts back to 0 implicitly via a fresh
  // publishCloudflareTracks() call path (see stopPublishing()).
  _schedulePublishReconnectNotice() {
    if (this._publishReconnectTimer) return;
    if (this._publishReconnectAttempts >= 3) {
      console.warn('[AudioStreamHelper] Publish reconnect gave up after 3 attempts');
      window.dispatchEvent(new CustomEvent('lynkAudioPublishLost'));
      return;
    }
    const attempt = this._publishReconnectAttempts;
    this._publishReconnectAttempts++;
    const delayMs = 1000 * Math.pow(2, attempt);
    this._publishReconnectTimer = setTimeout(() => {
      this._publishReconnectTimer = null;
      if (this._publishStopped) return;
      window.dispatchEvent(new CustomEvent('lynkAudioPublishNeedsReconnect'));
    }, delayMs);
  },

  // The RTCRtpSender for the published audio track — kept so
  // toggleMicEnabled() can swap the track via replaceTrack() on mute/unmute
  // instead of stopping the track outright, which would otherwise kill the
  // Cloudflare publish permanently (see toggleMicEnabled's own comment).
  audioSender: null,

  // forceReconnect: true always tears down and recreates the peer
  // connection first, even if one already exists — needed by the
  // publish-reconnect flow, since a failed/disconnected peerConnection is
  // still non-null (ICE failure doesn't null it out), so the normal
  // "only init if missing" guard below would otherwise try to reuse a
  // dead connection instead of replacing it (matches Cloudflare's own
  // guidance: replace the connection, don't ICE-restart the same one).
  //
  // trackName: defaults to 'audio' (today's single-publisher behavior,
  // unchanged for existing callers) — multi-speaker calls pass the
  // speaker's own user id instead, so Cloudflare's (sessionId, trackName)
  // pair uniquely addresses this specific speaker's track, not just "the
  // call's audio." See social.forum_call_participants.track_name.
  async publishCloudflareTracks(appId, sessionId, edgeFunctionUrl, authToken, forumId, forceReconnect = false, trackName = 'audio') {
    try {
      if (!this.peerConnection || forceReconnect) {
        await this.initCloudflarePeerConnection(appId, sessionId);
      }
      this._publishReconnectAttempts = 0;
      if (!this.localAudioStream) return false;

      const audioTrack = this.localAudioStream.getAudioTracks()[0];
      if (!audioTrack) return false;

      const transceiver = this.peerConnection.addTransceiver(audioTrack, { direction: 'sendonly' });
      this.audioSender = transceiver.sender;

      const offer = await this.peerConnection.createOffer();
      await this.peerConnection.setLocalDescription(offer);

      // transceiver.mid is null until setLocalDescription() has run — see
      // the matching fix/comment in lynkVideoStreamHelper.publishCloudflareTracks.
      const tracks = [{
        location: 'local',
        mid: transceiver.mid,
        trackName: trackName
      }];

      if (!appId || !sessionId) {
        console.warn('[AudioStreamHelper] publishCloudflareTracks: missing appId/sessionId');
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
          await this.peerConnection.setRemoteDescription(new RTCSessionDescription(data.sessionDescription));
          console.log('[AudioStreamHelper] Cloudflare Calls WebRTC stream published successfully');
          return true;
        }
      } else {
        console.warn('[AudioStreamHelper] publish_track request failed:', res.status);
      }
    } catch (e) {
      console.warn('[AudioStreamHelper] Cloudflare Calls publish error:', e);
    }
    return false;
  },

  // Mutes/unmutes the host's published audio by swapping the sender's
  // track via replaceTrack() — NOT by stopping the local track, which would
  // kill the transceiver's send permanently (replaceTrack(null) still keeps
  // the sender/transceiver alive, just silent; a later replaceTrack(track)
  // resumes it on the SAME already-negotiated connection, no renegotiation
  // or re-publish needed). Previously this called stopLocalMicrophone() on
  // mute (which stops the MediaStreamTrack outright) and
  // startLocalMicrophone() on unmute (which creates an unrelated NEW track
  // that was never attached to audioSender) — so a single mute/unmute cycle
  // during a real call silently ended the host's Cloudflare publish for
  // good, with no error and no UI signal, since the local mute toggle still
  // looked like it worked.
  async toggleMicEnabled(enabled) {
    if (!this.audioSender) return;
    try {
      if (!enabled) {
        await this.audioSender.replaceTrack(null);
      } else {
        if (!this.localAudioStream) {
          await this.startLocalMicrophone();
        }
        const track = this.localAudioStream && this.localAudioStream.getAudioTracks()[0];
        if (track) {
          await this.audioSender.replaceTrack(track);
        }
      }
    } catch (e) {
      console.warn('[AudioStreamHelper] toggleMicEnabled error:', e);
    }
  },

  // Tears down the host's own publish-side peer connection. Does NOT touch
  // localAudioStream itself (stopLocalMicrophone's job) — this only stops
  // sending it to Cloudflare.
  stopPublishing() {
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
  },

  // Maps a transceiver's mid to the participant userId it was requested
  // for — populated by addParticipantTrack() (and the single-speaker
  // joinAsListener path, keyed 'host') from the mid Cloudflare's
  // tracks/new response returns for each requested track, so ontrack
  // (which only ever gets a bare transceiver.mid, no participant
  // identity) can route each incoming stream to that participant's own
  // <audio> element instead of all of them colliding on one shared
  // element.
  _midToParticipantId: {},

  initCloudflareListenerConnection() {
    if (this.listenerPeerConnection) {
      try { this.listenerPeerConnection.close(); } catch (_) {}
    }
    this._midToParticipantId = {};
    this.listenerPeerConnection = new RTCPeerConnection({
      iceServers: [{ urls: 'stun:stun.cloudflare.com:3478' }]
    });
    this.listenerPeerConnection.ontrack = (event) => {
      if (!event.streams || !event.streams[0]) return;
      const mid = event.transceiver && event.transceiver.mid;
      const participantId = mid != null ? this._midToParticipantId[mid] : null;
      if (participantId && participantId !== 'host') {
        this.bindRemoteParticipantStream(participantId, event.streams[0]);
      } else {
        // Single-speaker path (today's host-only call) — unchanged.
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
          // Needed by addParticipantTrack() to add further co-hosts' tracks to
          // this same connection later.
          this.cfListenerSessionId = data.listenerSessionId;
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

  // Adds a co-host's track to the EXISTING listener connection (does not
  // touch whatever is already flowing) — the multi-speaker counterpart to
  // joinAsListener, which always creates a fresh connection and is only
  // for the first (host) track. Requires listenerPeerConnection to
  // already exist (call joinAsListener first for the host's own track).
  // Per Cloudflare's docs this needs a two-step exchange, NOT the
  // offer-first flow pull_remote_track/join_as_listener use: the server
  // returns a fresh OFFER (requiresImmediateRenegotiation), which this
  // answers via a separate renegotiate_listener call — verified against
  // Cloudflare's own OpenAPI schema rather than assumed.
  async addParticipantTrack(edgeFunctionUrl, authToken, forumId, participantUserId, remoteSessionId, remoteTrackName) {
    if (!this.listenerPeerConnection) {
      console.warn('[AudioStreamHelper] addParticipantTrack: no existing listener connection — call joinAsListener first');
      return false;
    }

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
        console.warn('[AudioStreamHelper] add_remote_track request failed:', res.status);
        return false;
      }

      const data = await res.json();
      if (!data.sessionDescription || !data.sessionDescription.sdp) {
        console.warn('[AudioStreamHelper] add_remote_track: no offer in response');
        return false;
      }

      // The new track's mid — recorded BEFORE setRemoteDescription so
      // ontrack (which can fire synchronously during setRemoteDescription)
      // already has it available for routing.
      const newTrackInfo = (data.tracks || []).find(t => t.trackName === remoteTrackName);
      if (newTrackInfo && newTrackInfo.mid != null) {
        this._midToParticipantId[newTrackInfo.mid] = participantUserId;
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
        console.warn('[AudioStreamHelper] renegotiate_listener request failed:', renegRes.status);
        return false;
      }

      console.log('[AudioStreamHelper] Added participant track successfully:', participantUserId);
      return true;
    } catch (e) {
      console.warn('[AudioStreamHelper] addParticipantTrack error:', e);
      return false;
    }
  },

  // Removes a co-host's track — stops hearing them, detaches their
  // <audio> element, and clears their mid mapping. Does NOT renegotiate
  // the connection or notify Cloudflare: the transceiver is simply left
  // in place receiving a track that stops arriving once the participant's
  // own publish ends (Cloudflare tears down the publisher-side track,
  // which naturally stops delivery here) — matching the existing mute
  // pattern (replaceTrack(null)) of leaving connections alone rather than
  // renegotiating for every state change.
  removeParticipantTrack(participantUserId) {
    this.unbindRemoteParticipantStream(participantUserId);
    for (const mid of Object.keys(this._midToParticipantId)) {
      if (this._midToParticipantId[mid] === participantUserId) {
        delete this._midToParticipantId[mid];
      }
    }
  },

  // Tears down the listener-side peer connection and detaches the remote
  // stream from the audio element. Does NOT touch localAudioStream (the
  // listener's own mic, if they're also speaking) — that's stopLocalMicrophone's job.
  stopListening() {
    this._listenerStopped = true;
    this._listenerParams = null;
    this._listenerReconnectAttempts = 0;
    this.cfListenerSessionId = null;
    this._midToParticipantId = {};
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
    for (const userId of Object.keys(this._remoteParticipantElements)) {
      this.unbindRemoteParticipantStream(userId);
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
      // el plays the REMOTE host stream (see bindRemoteStream) — resume
      // the remote analyser's context, not the local mic's.
      if (this.remoteAudioContext && this.remoteAudioContext.state === 'suspended') {
        this.remoteAudioContext.resume();
      }
    }
  },

  // [source] is 'local' (this user's own mic — startLocalMicrophone) or
  // 'remote' (the pulled host stream — bindRemoteStream). Each gets its
  // own AudioContext/AnalyserNode so setting one up never tears down the
  // other — see the field comments above for why that matters (a listener
  // who becomes a co-host needs BOTH to keep working independently).
  setupAudioAnalyser(stream, source) {
    try {
      this.stopAudioAnalyser(source);
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx || !stream) return;

      const ctx = new AudioCtx();
      const node = ctx.createMediaStreamSource(stream);

      // 1. High-Pass Filter (85Hz) — Removes low frequency HVAC/fan rumble & desk thumps
      const highPassFilter = ctx.createBiquadFilter();
      highPassFilter.type = 'highpass';
      highPassFilter.frequency.value = 85;

      // 2. Vocal Presence EQ Filter (3kHz Peaking) — Boosts vocal clarity and speech pickup
      const presenceEq = ctx.createBiquadFilter();
      presenceEq.type = 'peaking';
      presenceEq.frequency.value = 3000;
      presenceEq.Q.value = 1.0;
      presenceEq.gain.value = 3.0; // +3dB boost for voice clarity

      // 3. Dynamics Compressor Node — Smooths voice dynamics and prevents clipping
      const compressorNode = ctx.createDynamicsCompressor();
      compressorNode.threshold.value = -24;
      compressorNode.knee.value = 30;
      compressorNode.ratio.value = 12;
      compressorNode.attack.value = 0.003;
      compressorNode.release.value = 0.25;

      const analyser = ctx.createAnalyser();
      analyser.fftSize = 64;

      // Connect DSP chain: Source -> HighPass -> Presence EQ -> Compressor -> Analyser
      node.connect(highPassFilter);
      highPassFilter.connect(presenceEq);
      presenceEq.connect(compressorNode);
      compressorNode.connect(analyser);

      const bufferLength = analyser.frequencyBinCount;
      if (source === 'local') {
        this.localAudioContext = ctx;
        this.localAnalyserNode = analyser;
        this.localAnalyserDataArray = new Uint8Array(bufferLength);
      } else {
        this.remoteAudioContext = ctx;
        this.remoteAnalyserNode = analyser;
        this.remoteAnalyserDataArray = new Uint8Array(bufferLength);
      }
    } catch (e) {
      console.warn('[AudioStreamHelper] Analyser setup failed:', e);
    }
  },

  // Prefers the LOCAL analyser (this user's own mic) when one exists —
  // "am I audible right now" is the more actionable signal once a user is
  // publishing — falling back to the REMOTE one for a pure listener who
  // has no local analyser at all.
  getAudioLevel() {
    const useLocal = !!(this.localAnalyserNode && this.localAnalyserDataArray);
    const analyserNode = useLocal ? this.localAnalyserNode : this.remoteAnalyserNode;
    const dataArray = useLocal ? this.localAnalyserDataArray : this.remoteAnalyserDataArray;
    const ctx = useLocal ? this.localAudioContext : this.remoteAudioContext;
    if (!analyserNode || !dataArray) return 0.0;
    if (ctx && ctx.state === 'suspended') {
      ctx.resume().catch(() => {});
    }
    analyserNode.getByteFrequencyData(dataArray);
    let sum = 0;
    for (let i = 0; i < dataArray.length; i++) {
      sum += dataArray[i];
    }
    const average = sum / dataArray.length;
    // Divisor lowered from 128 — the compressor node upstream (see
    // setupAudioAnalyser) keeps normal speech well below byte-max 255, so
    // 128 made the visualization look sluggish/under-sensitive for
    // ordinary speaking volume. 48 brings moderate speech up near the
    // visualization's useful range while Math.min still caps loud input
    // at 1.0.
    const level = Math.min(1.0, average / 48.0);
    return level;
  },

  // [source] omitted clears BOTH (full teardown, e.g. page/call end).
  stopAudioAnalyser(source) {
    if ((!source || source === 'local') && this.localAudioContext) {
      try {
        this.localAudioContext.close();
      } catch (_) {}
      this.localAudioContext = null;
      this.localAnalyserNode = null;
      this.localAnalyserDataArray = null;
    }
    if ((!source || source === 'remote') && this.remoteAudioContext) {
      try {
        this.remoteAudioContext.close();
      } catch (_) {}
      this.remoteAudioContext = null;
      this.remoteAnalyserNode = null;
      this.remoteAnalyserDataArray = null;
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
    this.stopPublishing();
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
  audioSender: null,
  videoSender: null,

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
          track = newStream.getAudioTracks()[0];
          if (track && this.videoStream) {
            this.videoStream.addTrack(track);
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

      const offer = await this.peerConnection.createOffer();
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
