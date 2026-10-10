// PWA Background Audio & Media Session Helper for Lynk-X
// Manages HTML5 audio DOM node, OS MediaSession metadata/controls,
// Screen WakeLock API, Web Audio AnalyserNode, local microphone capture, and page visibility re-hydration.
// The camera/video broadcast helper (window.lynkVideoStreamHelper) lives in video_stream_helper.js.

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
  _localEnvelope: 0.0,
  _remoteEnvelope: 0.0,
  // One analyser per pulled co-host, keyed by userId — see
  // bindRemoteParticipantStream's own comment for why the single local/
  // remote pair above isn't enough once more than one remote track can
  // be live at once.
  _participantAnalysers: {},
  localAudioStream: null,
  _micProcessing: null,

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
      // Raw mic -> RNNoise/dynamics chain; localAudioStream is the PROCESSED stream so
      // publishing, muting and the level meter all see what listeners hear.
      const raw = await navigator.mediaDevices.getUserMedia({
        audio: window.lynkMicProcessor.audioConstraints()
      });
      this._micProcessing = await window.lynkMicProcessor.process(raw);
      const stream = this._micProcessing.stream;
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
    if (this._micProcessing) {
      this._micProcessing.dispose();
      this._micProcessing = null;
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
    // Each pulled co-host gets their OWN analyser — getAudioLevel()'s
    // local/remote split only ever reports ONE level for the whole page
    // (this user's own mic, or whatever single remote stream they're
    // pulling), so a grid of co-host tiles had no way to tell who among
    // them was actually speaking; every tile shared the same reading.
    this.setupParticipantAnalyser(userId, stream);
  },

  unbindRemoteParticipantStream(userId) {
    const el = this._remoteParticipantElements[userId];
    if (!el) return;
    el.pause();
    el.srcObject = null;
    el.remove();
    delete this._remoteParticipantElements[userId];
    this.stopParticipantAnalyser(userId);
  },

  listenerPeerConnection: null,
  cfListenerSessionId: null,
  _listenerReconnectAttempts: 0,
  _listenerReconnectTimer: null,
  _listenerParams: null,
  _listenerStopped: false,
  _audioStallWatchdogTimer: null,
  _lastInboundAudioBytes: 0,
  _audioStallStrikes: 0,
  _audioListenerStartedAt: 0,

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

      const rawOffer = await this.peerConnection.createOffer();
      const offer = { type: rawOffer.type, sdp: window.lynkMicProcessor.tuneOpusForVoice(rawOffer.sdp) };
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
          // The sender's Opus encoder is configured from the REMOTE description, so the voice
          // tuning has to be applied to the answer too — tuning only our offer would be ignored.
          await this.peerConnection.setRemoteDescription(new RTCSessionDescription({
            type: data.sessionDescription.type,
            sdp: window.lynkMicProcessor.tuneOpusForVoice(data.sessionDescription.sdp)
          }));
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
    this._stopInboundAudioWatchdog();
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
    this._stopInboundAudioWatchdog();
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
    console.log(`[AudioStreamHelper] Listener connection ${this.listenerPeerConnection && this.listenerPeerConnection.iceConnectionState}, retrying in ${delayMs}ms (attempt ${attempt + 1}/3)`);
    // Lets Dart show a "Reconnecting…" state while a retry is in flight,
    // rather than only learning about trouble once all 3 attempts are
    // exhausted (lynkAudioListenerLost, below).
    window.dispatchEvent(new CustomEvent('lynkAudioListenerReconnecting'));

    this._listenerReconnectTimer = setTimeout(async () => {
      this._listenerReconnectTimer = null;
      if (this._listenerStopped || !this._listenerParams) return;
      const p = this._listenerParams;
      await this.joinAsListener(p.edgeFunctionUrl, p.authToken, p.forumId, p.remoteSessionId, p.remoteTrackName);
    }, delayMs);
  },

  // Inbound audio stall watchdog: detects when WebRTC claims the connection
  // is 'connected' or 'completed', but inbound bytes have completely frozen
  // (e.g. mobile radio handoff, edge routing stall, or suspended decoder).
  _startInboundAudioWatchdog() {
    this._stopInboundAudioWatchdog();
    this._lastInboundAudioBytes = 0;
    this._audioStallStrikes = 0;
    this._audioListenerStartedAt = performance.now();

    const WARMUP_MS = 4000;
    const MAX_STRIKES = 5; // 5 consecutive seconds with 0 new audio bytes received while connected

    this._audioStallWatchdogTimer = setInterval(async () => {
      if (this._listenerStopped || !this.listenerPeerConnection) {
        this._stopInboundAudioWatchdog();
        return;
      }

      // Allow 4s warm-up for ICE negotiation and media buffers to start flowing
      if (performance.now() - this._audioListenerStartedAt < WARMUP_MS) return;

      const pc = this.listenerPeerConnection;
      const iceState = pc.iceConnectionState;

      // Only evaluate when ICE claims the connection is alive/working
      if (iceState !== 'connected' && iceState !== 'completed') {
        this._audioStallStrikes = 0;
        return;
      }

      try {
        let currentBytes = 0;
        let hasInboundAudio = false;

        const stats = await pc.getStats();
        stats.forEach((report) => {
          if (report.type === 'inbound-rtp' && report.kind === 'audio') {
            hasInboundAudio = true;
            if (report.bytesReceived !== undefined) {
              currentBytes += report.bytesReceived;
            }
          }
        });

        if (!hasInboundAudio) return;

        // If bytes received hasn't advanced while connected, count a strike
        if (this._lastInboundAudioBytes > 0 && currentBytes <= this._lastInboundAudioBytes) {
          this._audioStallStrikes++;
          console.warn(`[AudioStreamHelper] Inbound audio stall detected (strike ${this._audioStallStrikes}/${MAX_STRIKES})`);

          if (this._audioStallStrikes >= MAX_STRIKES) {
            console.warn('[AudioStreamHelper] Inbound audio stall sustained for 5s — triggering watchdog reconnect');
            this._stopInboundAudioWatchdog();
            this._scheduleListenerReconnect();
            return;
          }
        } else {
          this._audioStallStrikes = 0;
        }

        this._lastInboundAudioBytes = currentBytes;
      } catch (err) {
        console.warn('[AudioStreamHelper] Watchdog stats check error:', err);
      }
    }, 1000);
  },

  _stopInboundAudioWatchdog() {
    if (this._audioStallWatchdogTimer) {
      clearInterval(this._audioStallWatchdogTimer);
      this._audioStallWatchdogTimer = null;
    }
    this._audioStallStrikes = 0;
    this._lastInboundAudioBytes = 0;
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
          // Only a genuine recovery (this call followed at least one
          // _scheduleListenerReconnect retry) needs to tell Dart the
          // "Reconnecting…" state is over — a first-time join never set it.
          if (this._listenerReconnectAttempts > 0) {
            window.dispatchEvent(new CustomEvent('lynkAudioListenerReconnected'));
          }
          this._listenerReconnectAttempts = 0;
          this._startInboundAudioWatchdog();
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
    this._stopInboundAudioWatchdog();
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

  // Shared DSP chain builder — same high-pass/presence-EQ/compressor/
  // analyser pipeline used for the local mic, the single remote pull, and
  // (below) each individually pulled co-host, so there's one place that
  // defines "what does this app consider a good voice-analysis chain"
  // rather than three copies that could drift apart.
  _buildAnalyserChain(ctx, stream) {
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

    return analyser;
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
      const analyser = this._buildAnalyserChain(ctx, stream);
      const bufferLength = analyser.frequencyBinCount;
      if (source === 'local') {
        this.localAudioContext = ctx;
        this.localAnalyserNode = analyser;
        this.localAnalyserDataArray = new Uint8Array(bufferLength);
        this._localEnvelope = 0.0;
      } else {
        this.remoteAudioContext = ctx;
        this.remoteAnalyserNode = analyser;
        this.remoteAnalyserDataArray = new Uint8Array(bufferLength);
        this._remoteEnvelope = 0.0;
      }
    } catch (e) {
      console.warn('[AudioStreamHelper] Analyser setup failed:', e);
    }
  },

  // One analyser per co-host, keyed by userId — see
  // bindRemoteParticipantStream's own comment.
  setupParticipantAnalyser(userId, stream) {
    try {
      this.stopParticipantAnalyser(userId);
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx || !stream) return;

      const ctx = new AudioCtx();
      const analyser = this._buildAnalyserChain(ctx, stream);
      this._participantAnalysers[userId] = {
        ctx,
        analyser,
        dataArray: new Uint8Array(analyser.frequencyBinCount),
        envelope: 0.0,
      };
    } catch (e) {
      console.warn('[AudioStreamHelper] Participant analyser setup failed:', e);
    }
  },

  stopParticipantAnalyser(userId) {
    const entry = this._participantAnalysers[userId];
    if (!entry) return;
    entry.ctx.close().catch(() => {});
    delete this._participantAnalysers[userId];
  },

  // Same dB-normalization + attack/release envelope as getAudioLevel()
  // below, applied to one co-host's own pulled-track analyser. Returns
  // 0.0 if that userId has no analyser (never pulled, or already left).
  getParticipantAudioLevel(userId) {
    const entry = this._participantAnalysers[userId];
    if (!entry) return 0.0;
    if (entry.ctx.state === 'suspended') {
      entry.ctx.resume().catch(() => {});
    }
    entry.analyser.getByteFrequencyData(entry.dataArray);
    let sum = 0;
    for (let i = 0; i < entry.dataArray.length; i++) {
      sum += entry.dataArray[i];
    }
    const average = sum / entry.dataArray.length;
    const targetLevel = this._dbNormalize(average);
    entry.envelope = this._applyEnvelope(entry.envelope, targetLevel);
    return entry.envelope;
  },

  _dbFloor: -55,
  _dbCeiling: -10,
  _attackSeconds: 0.03,
  _releaseSeconds: 0.25,
  _envelopeDtSeconds: 0.09,

  // Byte-domain average (0-255) -> dB, then normalized against
  // _dbFloor/_dbCeiling -> 0.0-1.0. Human perceived loudness is
  // logarithmic, so this (not a linear average/divisor) is what gives
  // normal speech a usable range of motion instead of behaving like an
  // on/off switch.
  _dbNormalize(average) {
    if (average <= 0) return 0.0;
    const db = 20 * Math.log10(average / 255);
    const level = (db - this._dbFloor) / (this._dbCeiling - this._dbFloor);
    return Math.max(0.0, Math.min(1.0, level));
  },

  // Exponential attack/release envelope toward targetLevel — this is what
  // actually makes a level meter animate rather than jump straight to
  // whatever the current instantaneous reading is.
  _applyEnvelope(prevEnvelope, targetLevel) {
    const tau = targetLevel > prevEnvelope ? this._attackSeconds : this._releaseSeconds;
    const alpha = 1 - Math.exp(-this._envelopeDtSeconds / tau);
    return prevEnvelope + (targetLevel - prevEnvelope) * alpha;
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
    const targetLevel = this._dbNormalize(average);

    const prevEnvelope = useLocal ? this._localEnvelope : this._remoteEnvelope;
    const envelope = this._applyEnvelope(prevEnvelope, targetLevel);

    if (useLocal) {
      this._localEnvelope = envelope;
    } else {
      this._remoteEnvelope = envelope;
    }
    return envelope;
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
