import 'package:supabase_flutter/supabase_flutter.dart';

class EventRepository {
  final SupabaseClient _client;
  EventRepository(this._client);

  /// Keyset-paginated: pass the (event_starts_at, forum_id) of the last row
  /// from the previous page as [afterStartsAt]/[afterForumId] to fetch the
  /// next page. Omit both for the first page.
  Future<List<Map<String, dynamic>>> getUserForums(
    String userId, {
    int limit = 15,
    String? afterStartsAt,
    String? afterForumId,
  }) async {
    var query = _client
        .schema('api')
        .from('v1_user_forums')
        .select()
        .eq('user_id', userId);

    if (afterStartsAt != null && afterForumId != null) {
      // (event_starts_at, forum_id) > (cursor) — matches the ASC ordering below.
      query = query.or(
        'event_starts_at.gt.$afterStartsAt,'
        'and(event_starts_at.eq.$afterStartsAt,forum_id.gt.$afterForumId)',
      );
    }

    final data = await query
        .order('event_starts_at', ascending: true)
        .order('forum_id', ascending: true)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data);
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
