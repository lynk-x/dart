import 'package:supabase_flutter/supabase_flutter.dart';

class ForumRepository {
  final SupabaseClient _client;
  ForumRepository(this._client);

  /// Forum screen entry point: profile, forum (by id or reference), the
  /// caller's membership row, first channel, sessions, and member list in
  /// one call. Replaces what used to be 6 sequential queries split across
  /// getForumWithMemberStatus(ByReference), getForumMembers, and
  /// getForumSessions — those are removed as of this change, superseded by
  /// api.get_forum_data (renamed from api.get_forum_bootstrap to match the
  /// backend's get_* RPC naming convention).
  Future<Map<String, dynamic>> getForumData(String reference) async {
    final data = await _client
        .schema('api')
        .rpc('get_forum_data', params: {'p_reference': reference});
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<Map<String, dynamic>>> getForumMembers(String forumId) async {
    final data = await _client
        .schema('api')
        .from('v1_forum_members')
        .select('user_id, user_name, avatar_url, is_premium, role_id')
        .eq('forum_id', forumId);

    return data
        .map((item) => {
              'user_profile': {
                'id': item['user_id'],
                'user_name': item['user_name'],
                'avatar_url': item['avatar_url'],
                'is_premium': item['is_premium'],
                'role_id': item['role_id'],
                'is_organizer': item['role_id'] == 'organizer',
                'is_moderator': item['role_id'] == 'moderator',
              }
            })
        .toList();
  }

  Future<void> updateMemberSettings(
      String forumId, String userId, Map<String, dynamic> data) async {
    await _client
        .schema('social')
        .from('forum_members')
        .update(data)
        .eq('forum_id', forumId)
        .eq('user_id', userId);
  }

  Future<void> updateForumStatus(String forumId, String status) async {
    await _client
        .schema('social')
        .from('forums')
        .update({'status': status}).eq('id', forumId);
  }

  Future<void> promoteForumMember(String forumId, String userId) async {
    await _client.schema('api').rpc('promote_forum_member', params: {
      'p_forum_id': forumId,
      'p_target_user_id': userId,
    });
  }

  Future<void> markForumAsRead(String forumId) async {
    await _client
        .schema('api')
        .rpc('mark_forum_as_read', params: {'p_forum_id': forumId});
  }

  Future<void> moderateUser({
    required String targetUserId,
    required String action,
    required String forumId,
    String? reason,
  }) async {
    await _client.schema('api').rpc('moderate_user_safe', params: {
      'p_target_user_id': targetUserId,
      'p_action': action,
      'p_forum_id': forumId,
      'p_reason': reason ?? 'Violated forum rules',
    });
  }

  Future<bool> toggleReaction(
    String messageId,
    String messageCreatedAt,
    String userId,
    String emojiCode,
  ) async {
    // Partition pruning: Reaction's created_at must be >= message_created_at.
    final existing = await _client
        .schema('social')
        .from('message_reactions')
        .select('id, created_at')
        .eq('message_id', messageId)
        .eq('user_id', userId)
        .eq('emoji_code', emojiCode)
        .gte('created_at', messageCreatedAt)
        .maybeSingle();

    if (existing != null) {
      await _client
          .schema('social')
          .from('message_reactions')
          .delete()
          .eq('id', existing['id'] as String)
          .eq('created_at', existing['created_at'] as String);
      return false;
    } else {
      await _client.schema('social').from('message_reactions').insert({
        'message_id': messageId,
        'message_created_at': messageCreatedAt,
        'user_id': userId,
        'emoji_code': emojiCode,
      });
      return true;
    }
  }

  /// Goes through api.pin_message rather than a direct table UPDATE: the
  /// base ForumMessages RLS policy only allows a message's own author to
  /// edit it, so a moderator pinning someone else's message needs this
  /// SECURITY DEFINER RPC (which checks can_manage_forum itself) — a raw
  /// client-side update silently affected 0 rows for that case. Also
  /// enforces single-pin-per-forum server-side (auto-unpins any previously
  /// pinned message), matching the Updates tab's one-pin banner.
  Future<void> pinMessage(String messageId, DateTime createdAt) async {
    await _client.schema('api').rpc('pin_message', params: {
      'p_message_id': messageId,
      'p_created_at': createdAt.toIso8601String(),
    });
  }

  Future<void> unpinMessage(String messageId, DateTime createdAt) async {
    await _client.schema('api').rpc('unpin_message', params: {
      'p_message_id': messageId,
      'p_created_at': createdAt.toIso8601String(),
    });
  }

  Future<void> submitReport({
    String? targetUserId,
    String? messageId,
    String? targetMediaId,
    String? targetMediaCreatedAt,
    required String reasonId,
    required String description,
  }) async {
    await _client.schema('api').rpc('submit_report', params: {
      'p_target_user_id': targetUserId,
      'p_target_message_id': messageId,
      'p_target_media_id': targetMediaId,
      'p_target_media_created_at': targetMediaCreatedAt,
      'p_reason_id': reasonId,
      'p_description': description,
    });
  }

  Future<List<Map<String, dynamic>>> getMessages({
    required String forumId,
    int limit = 50,
    String? before,
    String? after,
    String? searchQuery,
    List<String>? messageTypes,
    String? hashtag,
  }) async {
    var query =
        _client.from('vw_forum_messages').select().eq('forum_id', forumId);

    if (messageTypes != null && messageTypes.isNotEmpty) {
      query = query.inFilter('message_type', messageTypes);
    }

    if (hashtag != null) {
      query = query.eq('hashtag', hashtag);
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query = query.textSearch('fts', searchQuery, config: 'english');
    }

    if (after == null) {
      query = query.filter('deleted_at', 'is', null);
    }

    if (before != null) {
      query = query.lt('created_at', before);
    }
    if (after != null) {
      query = query.gt('created_at', after);
    }

    final data = await query
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);

    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>> sendMessage(Map<String, dynamic> payload) async {
    final data = await _client
        .schema('social')
        .from('forum_messages')
        .insert(payload)
        .select()
        .single();
    return data;
  }

  Future<void> deleteMessage(String messageId, String createdAt) async {
    await _client
        .schema('social')
        .from('forum_messages')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', messageId)
        .eq('created_at', createdAt);
  }

  RealtimeChannel subscribeToMessages(
    String forumId,
    void Function(PostgresChangePayload) callback,
  ) {
    return _client.channel('forum_messages_$forumId').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'social',
          table: 'forum_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'forum_id',
            value: forumId,
          ),
          callback: callback,
        );
  }

  RealtimeChannel subscribeToForumChanges(
    String forumId,
    void Function(PostgresChangePayload) callback,
  ) {
    return _client.channel('forum_status_$forumId').onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'social',
          table: 'forums',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: forumId,
          ),
          callback: callback,
        );
  }

  RealtimeChannel subscribeToMemberChanges(
    String forumId,
    String userId,
    void Function(PostgresChangePayload) callback,
  ) {
    return _client.channel('forum_member_${forumId}_$userId').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'social',
          table: 'forum_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: callback,
        );
  }

  RealtimeChannel subscribeToMediaChanges(
    String forumId,
    void Function(PostgresChangePayload) callback,
  ) {
    return _client.channel('forum_media_$forumId').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'social',
          table: 'forum_media',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'forum_id',
            value: forumId,
          ),
          callback: callback,
        );
  }
}
