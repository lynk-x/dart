import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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

class ForumAudioStreamService {
  final SupabaseClient supabase;
  final String appId;
  final String appSecret;

  RealtimeChannel? _channel;

  ForumAudioStreamService({
    SupabaseClient? supabase,
    this.appId = '',
    this.appSecret = '',
  }) : supabase = supabase ?? Supabase.instance.client;

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

  /// Fetches initial streaming_config for a forum on open
  Future<Map<String, dynamic>?> fetchInitialStreamingConfig(String forumId) async {
    try {
      final data = await supabase
          .from('forums')
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
  }) {
    _channel?.unsubscribe();
    _channel = supabase.channel('forum_audio:$forumId');

    _channel!.onBroadcast(
      event: 'audio_stream_event',
      callback: (payload) {
        onEvent(payload);
      },
    ).subscribe();

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

  /// Creates a new Cloudflare Calls WebRTC Session via REST API
  Future<String?> createCloudflareSession() async {
    if (appId.isEmpty || appSecret.isEmpty) {
      // Mock session ID for local testing when Cloudflare credentials are unset
      return 'mock_cf_session_${DateTime.now().millisecondsSinceEpoch}';
    }

    try {
      final response = await http.post(
        Uri.parse('https://rtc.live.cloudflare.com/v1/apps/$appId/sessions/new'),
        headers: {
          'Authorization': 'Bearer $appSecret',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['sessionId'] as String?;
      }
    } catch (e) {
      debugPrint('[AudioStreamService] createCloudflareSession error: $e');
    }
    return 'mock_cf_session_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Updates streaming_config JSONB on v1_forums table in Supabase
  Future<void> updateForumStreamingConfig({
    required String forumId,
    required bool isLive,
    String? sessionId,
    String? hostId,
  }) async {
    _localConfigCache[forumId] = {
      'is_live': isLive,
      'stream_type': 'audio',
      'cf_session_id': sessionId,
      'active_host_id': hostId,
      'allow_multi_speaker': true,
    };
    try {
      await supabase.from('forums').update({
        'streaming_config': _localConfigCache[forumId]
      }).eq('id', forumId);
    } catch (e) {
      debugPrint('[AudioStreamService] updateForumStreamingConfig error: $e');
    }
  }
}
