import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ForumAudioStreamService {
  final SupabaseClient supabase;
  final String appId;
  final String appSecret;

  ForumAudioStreamService({
    required this.supabase,
    this.appId = '',
    this.appSecret = '',
  });

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
