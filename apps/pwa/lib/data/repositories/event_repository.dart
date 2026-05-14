import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_core/core.dart';

class EventRepository {
  final SupabaseClient _client;
  EventRepository(this._client);

  Future<List<EventModel>> getUserForums(
    String userId, {
    int limit = 15,
    int offset = 0,
  }) async {
    final data = await _client
        .schema('api')
        .from('v1_user_forums')
        .select()
        .eq('user_id', userId)
        .order('event_starts_at', ascending: true)
        .range(offset, offset + limit - 1);
    return data.map((json) => EventModel.fromMap(json)).toList();
  }

  Future<Map<String, dynamic>?> getEventById(String eventId) async {
    return await _client
        .schema('api')
        .from('v1_events')
        .select()
        .eq('id', eventId)
        .maybeSingle();
  }
}
