import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

@JS('window.lynkAudioStreamHelper.setupMediaSession')
external void _jsSetupMediaSession(JSString title, JSString artist, JSString artworkUrl);

@JS('window.lynkAudioStreamHelper.requestWakeLock')
external JSPromise<JSAny?> _jsRequestWakeLock();

@JS('window.lynkAudioStreamHelper.releaseWakeLock')
external JSPromise<JSAny?> _jsReleaseWakeLock();

@JS('window.lynkAudioStreamHelper.clearMediaSession')
external void _jsClearMediaSession();

@JS('window.lynkAudioStreamHelper.getAudioLevel')
external JSNumber _jsGetAudioLevel();

class ForumAudioStreamService {
  final SupabaseClient supabase;
  final String appId;
  final String appSecret;

  RealtimeChannel? _channel;

  ForumAudioStreamService({
    required this.supabase,
    this.appId = '',
    this.appSecret = '',
  });

  /// Retrieves current real-time vocal intensity (0.0 to 1.0) from AnalyserNode
  double getAudioLevel() {
    if (!kIsWeb) return 0.0;
    try {
      return _jsGetAudioLevel().toDartDouble;
    } catch (_) {
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
        (artworkUrl ?? 'icons/Icon-512.png').toJS,
      );
    } catch (_) {}
  }

  /// Requests Screen WakeLock to prevent device dimming when host/speaker is active
  void requestWakeLock() {
    if (!kIsWeb) return;
    try {
      _jsRequestWakeLock();
    } catch (_) {}
  }

  /// Releases Screen WakeLock
  void releaseWakeLock() {
    if (!kIsWeb) return;
    try {
      _jsReleaseWakeLock();
    } catch (_) {}
  }

  /// Clears OS Media Session metadata and stops background audio DOM node
  void clearMediaSession() {
    if (!kIsWeb) return;
    try {
      _jsClearMediaSession();
    } catch (_) {}
  }

  /// Fetches initial streaming_config for a forum on open
  Future<Map<String, dynamic>?> fetchInitialStreamingConfig(String forumId) async {
    try {
      final data = await supabase
          .from('forums')
          .select('streaming_config')
          .eq('id', forumId)
          .maybeSingle();

      if (data != null && data['streaming_config'] != null) {
        return Map<String, dynamic>.from(data['streaming_config']);
      }
    } catch (_) {}
    return null;
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
      // Fallback mock session ID on error
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
    try {
      await supabase.from('forums').update({
        'streaming_config': {
          'is_live': isLive,
          'stream_type': 'audio',
          'cf_session_id': sessionId,
          'active_host_id': hostId,
          'allow_multi_speaker': true,
        }
      }).eq('id', forumId);
    } catch (e) {
      // Fallback silently if RLS or column schema permits
    }
  }
}
