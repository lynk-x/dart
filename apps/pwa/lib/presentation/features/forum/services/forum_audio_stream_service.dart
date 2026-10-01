import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

@JS('window.lynkAudioStreamHelper.setupMediaSession')
external void _jsSetupMediaSession(JSString title, JSString artist, JSString artworkUrl);

@JS('window.lynkAudioStreamHelper.startLocalMicrophone')
external JSPromise<JSBoolean> _jsStartLocalMicrophone();

@JS('window.lynkAudioStreamHelper.stopLocalMicrophone')
external void _jsStopLocalMicrophone();

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

@JS('window.lynkAudioStreamHelper.getListenerAudioTelemetryStats')
external JSPromise<JSString> _jsGetListenerAudioTelemetryStats();

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

class ForumAudioStreamService {
  final SupabaseClient supabase;

  RealtimeChannel? _channel;
  JSFunction? _listenerLostListener;

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
    List<String>? activeSpeakers,
    Map<String, dynamic>? extraData,
  }) async {
    if (_channel == null) return;

    await _channel!.sendBroadcastMessage(
      event: 'audio_stream_event',
      payload: {
        'action': action,
        if (sessionId != null) 'sessionId': sessionId,
        if (hostId != null) 'hostId': hostId,
        if (activeSpeakers != null) 'activeSpeakers': activeSpeakers,
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
        return response.data?['sessionId'] as String?;
      }
      debugPrint('[AudioStreamService] createCloudflareSession returned status ${response.status}');
    } catch (e) {
      debugPrint('[AudioStreamService] createCloudflareSession error: $e');
    }
    // Falls back to a mock session only when the Edge Function itself is
    // unreachable (e.g. local dev without `supabase functions serve`) — not
    // when credentials are missing, since credentials no longer live here.
    return 'mock_cf_session_${DateTime.now().millisecondsSinceEpoch}';
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
  /// a missing summary row shouldn't block that.
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

  /// Updates streaming_config via the api.update_forum_streaming_config RPC
  /// (not a raw UPDATE against the retired public.forums proxy — see
  /// social.update_forum_streaming_config for the authorization check this
  /// now enforces explicitly).
  Future<void> updateForumStreamingConfig({
    required String forumId,
    required bool isLive,
    String? sessionId,
    String? hostId,
  }) async {
    final previousConfig = _localConfigCache[forumId];
    _localConfigCache[forumId] = {
      'is_live': isLive,
      'stream_type': 'audio',
      'cf_session_id': sessionId,
      'active_host_id': hostId,
      'allow_multi_speaker': true,
    };
    try {
      await supabase.schema('api').rpc('update_forum_streaming_config', params: {
        'p_forum_id': forumId,
        'p_is_live': isLive,
        'p_stream_type': 'audio',
        'p_session_id': sessionId,
        'p_host_id': hostId,
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
