import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;
import '../models/call_participant.dart';

@JS('window.lynkAudioStreamHelper.setupMediaSession')
external void _jsSetupMediaSession(JSString title, JSString artist, JSString artworkUrl);

@JS('window.lynkAudioStreamHelper.startLocalMicrophone')
external JSPromise<JSBoolean> _jsStartLocalMicrophone();

@JS('window.lynkAudioStreamHelper.stopLocalMicrophone')
external void _jsStopLocalMicrophone();

@JS('window.lynkAudioStreamHelper.toggleMicEnabled')
external JSPromise<JSAny?> _jsToggleMicEnabled(JSBoolean enabled);

@JS('window.lynkAudioStreamHelper.hasLocalMicrophone')
external JSBoolean _jsHasLocalMicrophone();

@JS('window.lynkAudioStreamHelper.requestWakeLock')
external JSPromise<JSAny?> _jsRequestWakeLock();

@JS('window.lynkAudioStreamHelper.releaseWakeLock')
external JSPromise<JSAny?> _jsReleaseWakeLock();

@JS('window.lynkAudioStreamHelper.clearMediaSession')
external void _jsClearMediaSession();

@JS('window.lynkAudioStreamHelper.getAudioLevel')
external JSNumber _jsGetAudioLevel();

@JS('window.lynkAudioStreamHelper.setBroadcastMuted')
external void _jsSetBroadcastMuted(JSBoolean muted);

@JS('window.lynkAudioStreamHelper.joinAsListener')
external JSPromise<JSBoolean> _jsJoinAsListener(
  JSString edgeFunctionUrl,
  JSString authToken,
  JSString forumId,
  JSString remoteSessionId,
  JSString remoteTrackName,
);

@JS('window.lynkAudioStreamHelper.stopListening')
external void _jsStopListening();

@JS('window.lynkAudioStreamHelper.addParticipantTrack')
external JSPromise<JSBoolean> _jsAddParticipantTrack(
  JSString edgeFunctionUrl,
  JSString authToken,
  JSString forumId,
  JSString participantUserId,
  JSString remoteSessionId,
  JSString remoteTrackName,
);

@JS('window.lynkAudioStreamHelper.removeParticipantTrack')
external void _jsRemoveParticipantTrack(JSString participantUserId);

@JS('window.lynkAudioStreamHelper.getListenerAudioTelemetryStats')
external JSPromise<JSString> _jsGetListenerAudioTelemetryStats();

@JS('window.lynkAudioStreamHelper.publishCloudflareTracks')
external JSPromise<JSBoolean> _jsPublishCloudflareTracks(
  JSString appId,
  JSString sessionId,
  JSString edgeFunctionUrl,
  JSString authToken,
  JSString forumId,
  JSBoolean forceReconnect,
  JSString trackName,
);

/// Receive-side quality for a listener's own audio connection — see
/// ForumAudioStreamService.listenerTelemetryNotifier.
class AudioCallTelemetry {
  final int rttMs;
  final String packetLossPercent;
  final int jitterMs;

  const AudioCallTelemetry({
    this.rttMs = 0,
    this.packetLossPercent = '0.0',
    this.jitterMs = 0,
  });

  /// Audio tolerates more jitter/loss than video before it's actually
  /// audible as choppy — thresholds are looser than TelemetryData
  /// .isPoorConnection's video-tuned 5%/250ms.
  bool get isPoorConnection {
    final loss = double.tryParse(packetLossPercent) ?? 0.0;
    return loss >= 8.0 || rttMs >= 400 || jitterMs >= 100;
  }
}

/// Mic/session lifecycle, participant registry, and Cloudflare Calls
/// JS-bridge calls for the forum's live audio call — the counterpart
/// [ForumAudioStreamCubit] drives via this service rather than talking to
/// Supabase/JS directly.
class ForumAudioStreamService {
  final SupabaseClient supabase;

  RealtimeChannel? _channel;
  JSFunction? _listenerLostListener;
  JSFunction? _publishNeedsReconnectListener;
  JSFunction? _publishLostListener;

  /// Set by createCloudflareSession() before publishCloudflareTracks() needs
  /// it — mirrors ForumVideoStreamService._cfAppId.
  String? _cfAppId;

  /// Receive-side quality for THIS listener's own connection to the call —
  /// independent of how clean the host's own upload/network is.
  final ValueNotifier<AudioCallTelemetry> listenerTelemetryNotifier =
      ValueNotifier<AudioCallTelemetry>(const AudioCallTelemetry());

  ForumAudioStreamService({
    SupabaseClient? supabase,
  }) : supabase = supabase ?? Supabase.instance.client;

  /// Registers [onLost] to fire when the JS layer's listener-side retry
  /// (see audio_stream_helper.js's _scheduleListenerReconnect) exhausts its
  /// 3 attempts and gives up reconnecting a dropped remote audio track.
  /// Call [removeListenerLostCallback] when done (e.g. cubit close()) to
  /// avoid leaking the JS-side event listener.
  void onRemoteAudioListenerLost(void Function() onLost) {
    if (!kIsWeb) return;
    removeListenerLostCallback();
    _listenerLostListener = ((web.Event event) => onLost()).toJS;
    web.window.addEventListener('lynkAudioListenerLost', _listenerLostListener);
  }

  void removeListenerLostCallback() {
    if (!kIsWeb || _listenerLostListener == null) return;
    web.window.removeEventListener('lynkAudioListenerLost', _listenerLostListener);
    _listenerLostListener = null;
  }

  /// Registers [onNeedsReconnect] to fire each time the JS layer's publish
  /// side detects its Cloudflare connection has failed/disconnected and
  /// wants to retry (bounded at 3 attempts, with backoff already applied
  /// JS-side before this fires) — see audio_stream_helper.js's
  /// _schedulePublishReconnectNotice. The JS layer can't recover this
  /// itself: Cloudflare's own guidance is to replace the connection (a NEW
  /// session), which requires a Supabase-authenticated session-creation
  /// call only Dart can make, plus persisting the new session id and
  /// telling listeners to rejoin — all driven from here, not JS.
  void onPublishNeedsReconnect(void Function() onNeedsReconnect) {
    if (!kIsWeb) return;
    removePublishReconnectCallbacks();
    _publishNeedsReconnectListener = ((web.Event event) => onNeedsReconnect()).toJS;
    web.window.addEventListener('lynkAudioPublishNeedsReconnect', _publishNeedsReconnectListener);
  }

  /// Registers [onLost] to fire once the JS layer's publish-reconnect
  /// attempts are exhausted (3 attempts) — the host's call could not be
  /// restored and the UI should tell them to end/restart it manually.
  void onPublishLost(void Function() onLost) {
    if (!kIsWeb) return;
    _publishLostListener = ((web.Event event) => onLost()).toJS;
    web.window.addEventListener('lynkAudioPublishLost', _publishLostListener);
  }

  void removePublishReconnectCallbacks() {
    if (!kIsWeb) return;
    if (_publishNeedsReconnectListener != null) {
      web.window.removeEventListener('lynkAudioPublishNeedsReconnect', _publishNeedsReconnectListener);
      _publishNeedsReconnectListener = null;
    }
    if (_publishLostListener != null) {
      web.window.removeEventListener('lynkAudioPublishLost', _publishLostListener);
      _publishLostListener = null;
    }
  }

  /// Controls HTML5 audio element broadcast mute state on Web
  void setBroadcastMuted(bool muted) {
    if (!kIsWeb) return;
    try {
      _jsSetBroadcastMuted(muted.toJS);
    } catch (e) {
      debugPrint('[AudioStreamService] setBroadcastMuted error: $e');
    }
  }

  /// Captures local browser microphone media stream via navigator.mediaDevices.getUserMedia
  Future<bool> startLocalMicrophone() async {
    if (!kIsWeb) return true;
    try {
      final res = await _jsStartLocalMicrophone().toDart;
      return res.toDart;
    } catch (e) {
      debugPrint('[AudioStreamService] startLocalMicrophone error: $e');
      return false;
    }
  }

  /// Stops local microphone media stream and releases hardware track handles
  void stopLocalMicrophone() {
    if (!kIsWeb) return;
    try {
      _jsStopLocalMicrophone();
    } catch (e) {
      debugPrint('[AudioStreamService] stopLocalMicrophone error: $e');
    }
  }

  /// Mutes/unmutes the host's PUBLISHED audio (if currently publishing) by
  /// swapping the Cloudflare sender's track via replaceTrack(), instead of
  /// stopping/recreating the local MediaStreamTrack — the latter would kill
  /// the transceiver's send permanently on the next mute, since a freshly
  /// recreated track from startLocalMicrophone() is never reattached to the
  /// already-negotiated sender. No-op (safe to call) if nothing is
  /// currently being published, e.g. before publishCloudflareTracks() has
  /// run.
  Future<void> toggleMicEnabled(bool enabled) async {
    if (!kIsWeb) return;
    try {
      await _jsToggleMicEnabled(enabled.toJS).toDart;
    } catch (e) {
      debugPrint('[AudioStreamService] toggleMicEnabled error: $e');
    }
  }

  /// Whether a local microphone track is currently captured and live — used
  /// to avoid re-acquiring (and thereby destroying + replacing) the mic on
  /// an ordinary unmute, now that mute no longer stops the track outright.
  bool get hasLocalMicrophone {
    if (!kIsWeb) return false;
    try {
      return _jsHasLocalMicrophone().toDart;
    } catch (e) {
      return false;
    }
  }

  /// Retrieves current real-time vocal intensity (0.0 to 1.0) from AnalyserNode
  double getAudioLevel() {
    if (!kIsWeb) return 0.0;
    try {
      return _jsGetAudioLevel().toDartDouble;
    } catch (e) {
      return 0.0;
    }
  }

  /// Configures OS Media Session card (Lock screen / Notification shade)
  void configureMediaSession({
    required String title,
    required String artist,
    String? artworkUrl,
  }) {
    if (!kIsWeb) return;
    try {
      _jsSetupMediaSession(
        title.toJS,
        artist.toJS,
        (artworkUrl ?? 'icons/Icon-maskable-512.png').toJS,
      );
    } catch (e) {
      debugPrint('[AudioStreamService] configureMediaSession error: $e');
    }
  }

  /// Requests Screen WakeLock to prevent device dimming when host/speaker is active
  void requestWakeLock() {
    if (!kIsWeb) return;
    try {
      _jsRequestWakeLock();
    } catch (e) {
      debugPrint('[AudioStreamService] requestWakeLock error: $e');
    }
  }

  /// Releases Screen WakeLock
  void releaseWakeLock() {
    if (!kIsWeb) return;
    try {
      _jsReleaseWakeLock();
    } catch (e) {
      debugPrint('[AudioStreamService] releaseWakeLock error: $e');
    }
  }

  /// Clears OS Media Session metadata and stops background audio DOM node
  void clearMediaSession() {
    if (!kIsWeb) return;
    try {
      _jsClearMediaSession();
    } catch (e) {
      debugPrint('[AudioStreamService] clearMediaSession error: $e');
    }
  }

  final Map<String, Map<String, dynamic>> _localConfigCache = {};

  /// Fetches initial streaming_config for a forum on open. Reads through
  /// api.v1_forums — the versioned,
  /// read-only contract already exposes streaming_config.
  Future<Map<String, dynamic>?> fetchInitialStreamingConfig(String forumId) async {
    try {
      final data = await supabase
          .schema('api')
          .from('v1_forums')
          .select('streaming_config')
          .eq('id', forumId)
          .maybeSingle();

      if (data != null && data['streaming_config'] != null) {
        final config = Map<String, dynamic>.from(data['streaming_config']);
        _localConfigCache[forumId] = config;
        return config;
      }
    } catch (e) {
      debugPrint('[AudioStreamService] fetchInitialStreamingConfig error: $e');
    }
    return _localConfigCache[forumId];
  }

  /// Subscribes to realtime broadcast channel for a forum audio stream
  RealtimeChannel subscribeToAudioBroadcast({
    required String forumId,
    required void Function(Map<String, dynamic> payload) onEvent,
    void Function(RealtimeSubscribeStatus status)? onStatusChange,
  }) {
    _channel?.unsubscribe();
    _channel = supabase.channel('forum_audio:$forumId');

    _channel!.onBroadcast(
      event: 'audio_stream_event',
      callback: (payload) {
        onEvent(payload);
      },
    ).subscribe((status, [error]) {
      if (onStatusChange != null) {
        onStatusChange(status);
      }
    });

    return _channel!;
  }

  /// Broadcasts an audio stream event to all connected forum listeners via WebSocket
  Future<void> broadcastAudioEvent({
    required String action,
    String? sessionId,
    String? hostId,
    Map<String, dynamic>? extraData,
  }) async {
    if (_channel == null) return;

    await _channel!.sendBroadcastMessage(
      event: 'audio_stream_event',
      payload: {
        'action': action,
        if (sessionId != null) 'sessionId': sessionId,
        if (hostId != null) 'hostId': hostId,
        if (extraData != null) ...extraData,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// Unsubscribes from active realtime channel
  Future<void> unsubscribe() async {
    await _channel?.unsubscribe();
    _channel = null;
  }

  /// Joins an already-live host's audio session as a listener in a single
  /// Edge Function round-trip — session creation and remote track pull are
  /// combined server-side (join_as_listener) rather than two separate
  /// client round-trips, so a spike of listeners joining at once (e.g. a
  /// popular host starting a call) costs half the auth+membership-check
  /// work and half the latency per join. No Cloudflare credential ever
  /// reaches this client.
  ///
  /// The remote track name is always 'audio' — the host's publish side
  /// (createCloudflareSession + the JS publish call) hardcodes a single
  /// 'audio' track per session, so there is no per-speaker track to target
  /// here. A speaker_update event only changes who is unmuted on the
  /// host's existing published track; it does not require re-pulling.
  ///
  /// On a dropped connection, the JS layer retries automatically (bounded
  /// at 3 attempts) without this method being called again.
  Future<bool> subscribeToRemoteAudio({
    required String forumId,
    required String hostSessionId,
  }) async {
    if (!kIsWeb) return false;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
      final res = await _jsJoinAsListener(
        '$supabaseUrl/functions/v1'.toJS,
        (session?.accessToken ?? '').toJS,
        forumId.toJS,
        hostSessionId.toJS,
        'audio'.toJS,
      ).toDart;
      return res.toDart;
    } catch (e) {
      debugPrint('[AudioStreamService] subscribeToRemoteAudio error: $e');
      return false;
    }
  }

  /// Adds a co-host's track to the EXISTING listener connection — must be
  /// called after subscribeToRemoteAudio has already established a
  /// connection (pulling the host's track). The multi-speaker counterpart;
  /// does not disturb whatever is already flowing. See
  /// lynkAudioStreamHelper.addParticipantTrack for why this needs a
  /// different (server-offer, client-answer) exchange than the
  /// single-speaker pull.
  Future<bool> addParticipantTrack({
    required String forumId,
    required String participantUserId,
    required String remoteSessionId,
    required String remoteTrackName,
  }) async {
    if (!kIsWeb) return false;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
      final res = await _jsAddParticipantTrack(
        '$supabaseUrl/functions/v1'.toJS,
        (session?.accessToken ?? '').toJS,
        forumId.toJS,
        participantUserId.toJS,
        remoteSessionId.toJS,
        remoteTrackName.toJS,
      ).toDart;
      return res.toDart;
    } catch (e) {
      debugPrint('[AudioStreamService] addParticipantTrack error: $e');
      return false;
    }
  }

  /// Stops hearing a specific co-host — detaches their own <audio>
  /// element. Safe to call even if that participant's track was never added.
  void removeParticipantTrack(String participantUserId) {
    if (!kIsWeb) return;
    try {
      _jsRemoveParticipantTrack(participantUserId.toJS);
    } catch (e) {
      debugPrint('[AudioStreamService] removeParticipantTrack error: $e');
    }
  }

  /// Tears down the listener-side peer connection and stops playback of the
  /// remote host's audio. Safe to call even if never subscribed.
  void unsubscribeFromRemoteAudio() {
    if (!kIsWeb) return;
    try {
      _jsStopListening();
    } catch (e) {
      debugPrint('[AudioStreamService] unsubscribeFromRemoteAudio error: $e');
    }
  }

  /// Fetches receive-side WebRTC telemetry for a listener's own audio
  /// connection and updates [listenerTelemetryNotifier].
  Future<AudioCallTelemetry> fetchListenerTelemetryStats() async {
    if (!kIsWeb) return listenerTelemetryNotifier.value;
    try {
      final rawJson = await _jsGetListenerAudioTelemetryStats().toDart;
      final data = jsonDecode(rawJson.toDart) as Map<String, dynamic>;
      if (data['connected'] != true) return listenerTelemetryNotifier.value;

      final telemetry = AudioCallTelemetry(
        rttMs: (data['rttMs'] as num?)?.toInt() ?? 0,
        packetLossPercent: (data['packetLossPercent'] as String?) ?? '0.0',
        jitterMs: (data['jitterMs'] as num?)?.toInt() ?? 0,
      );
      listenerTelemetryNotifier.value = telemetry;
      return telemetry;
    } catch (e) {
      debugPrint('[AudioStreamService] fetchListenerTelemetryStats error: $e');
      return listenerTelemetryNotifier.value;
    }
  }

  /// Creates a new Cloudflare Calls WebRTC session via the cloudflare-calls-session
  /// Edge Function. The Cloudflare app secret is held server-side only — this
  /// never talks to rtc.live.cloudflare.com directly, so no credential is
  /// ever present in client code or network traffic.
  Future<String?> createCloudflareSession(String forumId) async {
    try {
      final response = await supabase.functions.invoke(
        'cloudflare-calls-session',
        body: {'action': 'create_session', 'forumId': forumId},
      );

      if (response.status == 200) {
        _cfAppId = response.data?['appId'] as String?;
        return response.data?['sessionId'] as String?;
      }
      debugPrint('[AudioStreamService] createCloudflareSession returned status ${response.status}');
    } catch (e) {
      debugPrint('[AudioStreamService] createCloudflareSession error: $e');
    }
    return null;
  }

  /// Publishes the host's local microphone track to Cloudflare Calls SFU.
  /// Must be called after startLocalMicrophone() and createCloudflareSession().
  /// [trackName] defaults to 'audio' (single-publisher); multi-speaker calls
  /// pass the speaker's own user id instead — see
  /// social.forum_call_participants.track_name.
  Future<bool> publishCloudflareTracks(
    String forumId,
    String sessionId, {
    bool forceReconnect = false,
    String trackName = 'audio',
  }) async {
    if (!kIsWeb) return true;
    try {
      final session = supabase.auth.currentSession;
      const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
      final res = await _jsPublishCloudflareTracks(
        (_cfAppId ?? '').toJS,
        sessionId.toJS,
        '$supabaseUrl/functions/v1'.toJS,
        (session?.accessToken ?? '').toJS,
        forumId.toJS,
        forceReconnect.toJS,
        trackName.toJS,
      ).toDart;
      return res.toDart;
    } catch (e) {
      debugPrint('[AudioStreamService] publishCloudflareTracks error: $e');
      return false;
    }
  }

  /// Opens a new social.forum_call_summaries row via the
  /// api.start_forum_call_summary RPC when a host starts a call —
  /// aggregate-only call history (no per-listener data, explicitly
  /// descoped). [hostId] is accepted for API symmetry with
  /// updateForumStreamingConfig's call sites, but the RPC derives the real
  /// host from the authenticated session (auth.uid()), not this param.
  /// Returns the new row's id so endCallSummary can close it; failures are
  /// swallowed (not critical-path — the call itself already started via
  /// updateForumStreamingConfig by the time this runs).
  Future<String?> startCallSummary({
    required String forumId,
    required DateTime forumCreatedAt,
    required String hostId,
    String? sessionId,
  }) async {
    try {
      final response = await supabase.schema('api').rpc('start_forum_call_summary', params: {
        'p_forum_id': forumId,
        'p_forum_created_at': forumCreatedAt.toIso8601String(),
        'p_stream_type': 'audio',
        'p_session_id': sessionId,
      });
      return response as String?;
    } catch (e) {
      debugPrint('[AudioStreamService] startCallSummary error: $e');
      return null;
    }
  }

  /// Sets ended_at on the call summary row created by [startCallSummary],
  /// via the api.end_forum_call_summary RPC. No-op if [summaryId] is null
  /// (e.g. the insert itself failed) — the call already ended either way;
  /// a missing summary row shouldn't block that. Server-side this also
  /// force-closes every still-open social.forum_call_participants row for
  /// the call (see that RPC's own comment) — no separate client-side
  /// cleanup of co-hosts/the host's own registry row is needed here.
  Future<void> endCallSummary(String? summaryId) async {
    if (summaryId == null) return;
    try {
      await supabase.schema('api').rpc('end_forum_call_summary', params: {
        'p_summary_id': summaryId,
      });
    } catch (e) {
      debugPrint('[AudioStreamService] endCallSummary error: $e');
    }
  }

  /// Claims a speaking slot in social.forum_call_participants for the
  /// calling user — the single source of truth for every active participant
  /// in a call, including the ORIGINAL HOST, who calls this the same way a
  /// self-joining co-host does. Returns the new participant row's id, or
  /// null on failure (cap reached, call ended, not an organizer).
  Future<String?> joinAsCallParticipant({
    required String forumId,
    required String callSummaryId,
    required String cfSessionId,
    required String trackName,
  }) async {
    try {
      final response = await supabase.schema('api').rpc('join_as_call_participant', params: {
        'p_forum_id': forumId,
        'p_call_summary_id': callSummaryId,
        'p_cf_session_id': cfSessionId,
        'p_track_name': trackName,
      });
      return response as String?;
    } catch (e) {
      debugPrint('[AudioStreamService] joinAsCallParticipant error: $e');
      return null;
    }
  }

  /// Host/organizer-only — grants [targetUserId] a speaking slot without
  /// requiring them to hold the organizer role themselves.
  Future<String?> inviteCallParticipant({
    required String forumId,
    required String callSummaryId,
    required String targetUserId,
    required String cfSessionId,
    required String trackName,
  }) async {
    try {
      final response = await supabase.schema('api').rpc('invite_call_participant', params: {
        'p_forum_id': forumId,
        'p_call_summary_id': callSummaryId,
        'p_user_id': targetUserId,
        'p_cf_session_id': cfSessionId,
        'p_track_name': trackName,
      });
      return response as String?;
    } catch (e) {
      debugPrint('[AudioStreamService] inviteCallParticipant error: $e');
      return null;
    }
  }

  /// Self-serve — voluntarily leaves the calling user's own speaking slot.
  Future<void> leaveCallParticipant(String callSummaryId) async {
    try {
      await supabase.schema('api').rpc('leave_call_participant', params: {
        'p_call_summary_id': callSummaryId,
      });
    } catch (e) {
      debugPrint('[AudioStreamService] leaveCallParticipant error: $e');
    }
  }

  /// Host/organizer-only — forcibly ends another participant's speaking
  /// slot.
  Future<void> removeCallParticipant({
    required String forumId,
    required String callSummaryId,
    required String targetUserId,
  }) async {
    try {
      await supabase.schema('api').rpc('remove_call_participant', params: {
        'p_forum_id': forumId,
        'p_call_summary_id': callSummaryId,
        'p_user_id': targetUserId,
      });
    } catch (e) {
      debugPrint('[AudioStreamService] removeCallParticipant error: $e');
    }
  }

  /// Self-serve — updates the calling user's OWN active participant row
  /// with a new Cloudflare address, after their publish connection was
  /// replaced (see _reconnectPublish in ForumAudioStreamCubit — Cloudflare's
  /// guidance is to replace the connection, not ICE-restart it, so the
  /// registry needs the new session id too, not just streaming_config).
  Future<void> updateParticipantSession({
    required String callSummaryId,
    required String cfSessionId,
    required String trackName,
  }) async {
    try {
      await supabase.schema('api').rpc('update_participant_session', params: {
        'p_call_summary_id': callSummaryId,
        'p_cf_session_id': cfSessionId,
        'p_track_name': trackName,
      });
    } catch (e) {
      debugPrint('[AudioStreamService] updateParticipantSession error: $e');
    }
  }

  /// Fetches the current active-speaker roster via api.v1_forum_call_participants
  /// — the bootstrap a listener/newly-joining client reconciles against
  /// before applying incremental participant_joined/participant_left
  /// broadcast events (see ForumAudioStreamCubit's registry handling).
  Future<Map<String, CallParticipant>> fetchCallParticipants(String callSummaryId) async {
    try {
      final rows = await supabase
          .schema('api')
          .from('v1_forum_call_participants')
          .select('user_id, user_name, full_name, cf_session_id, track_name')
          .eq('call_summary_id', callSummaryId);
      final participants = <String, CallParticipant>{};
      for (final row in rows) {
        final participant = CallParticipant.fromJson(row);
        if (participant.userId.isNotEmpty) participants[participant.userId] = participant;
      }
      return participants;
    } catch (e) {
      debugPrint('[AudioStreamService] fetchCallParticipants error: $e');
      return {};
    }
  }

  /// Updates streaming_config via the api.update_forum_streaming_config RPC
  /// (not a raw UPDATE against the retired public.forums proxy — see
  /// social.update_forum_streaming_config for the authorization check this
  /// now enforces explicitly).
  Future<void> updateForumStreamingConfig({
    required String forumId,
    required bool isLive,
    String? sessionId,
    String? hostId,
    String? callSummaryId,
  }) async {
    final previousConfig = _localConfigCache[forumId];
    _localConfigCache[forumId] = {
      'is_live': isLive,
      'stream_type': 'audio',
      'cf_session_id': sessionId,
      'active_host_id': hostId,
      'allow_multi_speaker': true,
      'call_summary_id': callSummaryId,
    };
    try {
      await supabase.schema('api').rpc('update_forum_streaming_config', params: {
        'p_forum_id': forumId,
        'p_is_live': isLive,
        'p_stream_type': 'audio',
        'p_session_id': sessionId,
        'p_host_id': hostId,
        'p_call_summary_id': callSummaryId,
      });
    } catch (e) {
      debugPrint('[AudioStreamService] updateForumStreamingConfig error: $e');
      // Roll back the local cache so a later fetchInitialStreamingConfig()
      // fallback doesn't report a write that never reached the server.
      if (previousConfig != null) {
        _localConfigCache[forumId] = previousConfig;
      } else {
        _localConfigCache.remove(forumId);
      }
      rethrow;
    }
  }
}
