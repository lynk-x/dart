import 'package:supabase_flutter/supabase_flutter.dart';

class EventRepository {
  final SupabaseClient _client;
  EventRepository(this._client);

  /// One keyset page of the caller's forums, in the order the home feed shows them: events that
  /// haven't ended yet come first (soonest end first), then ended events (most recent first).
  /// The server order matches the display order, so a later page only ever appends below what is
  /// already on screen instead of reshuffling it.
  ///
  /// [past] picks the half of the feed; [anchor] is a fixed "now" shared by every page of one feed
  /// session so an event ending between page fetches isn't returned twice or skipped. Pass the
  /// `event_ends_at` / `forum_id` of the previous page's last row as [afterEndsAt] /
  /// [afterForumId]; omit both for the first page of a half.
  Future<List<Map<String, dynamic>>> getUserForums(
    String userId, {
    int limit = 15,
    required bool past,
    required DateTime anchor,
    String? afterEndsAt,
    String? afterForumId,
  }) async {
    final anchorIso = anchor.toUtc().toIso8601String();
    var query = _client
        .schema('api')
        .from('v1_user_forums')
        .select()
        .eq('user_id', userId);

    query = past
        ? query.lt('event_ends_at', anchorIso)
        : query.gte('event_ends_at', anchorIso);

    if (afterEndsAt != null && afterForumId != null) {
      // Strictly after the cursor in this half's ordering (ASC for upcoming, DESC for past).
      final cmp = past ? 'lt' : 'gt';
      query = query.or(
        'event_ends_at.$cmp.$afterEndsAt,'
        'and(event_ends_at.eq.$afterEndsAt,forum_id.$cmp.$afterForumId)',
      );
    }

    final data = await query
        .order('event_ends_at', ascending: !past)
        .order('forum_id', ascending: !past)
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
