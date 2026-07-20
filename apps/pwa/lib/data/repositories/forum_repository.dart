import 'package:supabase_flutter/supabase_flutter.dart';

class ForumRepository {
  final SupabaseClient _client;
  ForumRepository(this._client);

  Future<Map<String, dynamic>> getForumWithMemberStatus(
      String forumId, String userId) async {
    final forumData = await _client
        .schema('api')
        .from('v1_forums')
        .select(
            'id, account_id, status, event_id, event_created_at, event_title, created_at, reference')
        .eq('id', forumId)
        .maybeSingle();

    final memberData = await _client
        .schema('social')
        .from('forum_members')
        .select('is_muted, has_muted_live_chats_media, role_id')
        .eq('forum_id', forumId)
        .eq('user_id', userId)
        .maybeSingle();

    final channelData = await _client
        .schema('social')
        .from('forum_channels')
        .select('id, created_at')
        .eq('forum_id', forumId)
        .limit(1)
        .maybeSingle();

    return {
      'forum': forumData,
      'member': memberData,
      'channel': channelData,
    };
  }

  Future<Map<String, dynamic>> getForumWithMemberStatusByReference(
      String reference, String userId) async {
    final isUuid = RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(reference);
    final query = _client.schema('api').from('v1_forums').select(
        'id, account_id, status, event_id, event_created_at, event_title, created_at, reference');

    final forumData = await (isUuid
        ? query.eq('id', reference).maybeSingle()
        : query.eq('reference', reference).maybeSingle());

    if (forumData == null) {
      return {
        'forum': null,
        'member': null,
        'channel': null,
      };
    }

    final forumId = forumData['id'] as String;

    final memberData = await _client
        .schema('social')
        .from('forum_members')
        .select('is_muted, has_muted_live_chats_media, role_id')
        .eq('forum_id', forumId)
        .eq('user_id', userId)
        .maybeSingle();

    final channelData = await _client
        .schema('social')
        .from('forum_channels')
        .select('id, created_at')
        .eq('forum_id', forumId)
        .limit(1)
        .maybeSingle();

    return {
      'forum': forumData,
      'member': memberData,
      'channel': channelData,
    };
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

  Future<List<Map<String, dynamic>>> getForumSessions(
    String forumId, {
    DateTime? forumCreatedAt,
  }) async {
    var query = _client
        .from('forum_sessions')
        .select('starts_at, ends_at')
        .eq('forum_id', forumId);

    if (forumCreatedAt != null) {
      query = query.eq('forum_created_at', forumCreatedAt.toIso8601String());
    }

    final data = await query.order('starts_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
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

  Future<void> updateMemberRole(
      String forumId, String userId, String roleId) async {
    await _client
        .schema('social')
        .from('forum_members')
        .update({'role_id': roleId})
        .eq('forum_id', forumId)
        .eq('user_id', userId);
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

  Future<void> pinMessage(String messageId) async {
    await _client
        .schema('social')
        .from('forum_messages')
        .update({'is_pinned': true}).eq('id', messageId);
  }

  Future<void> unpinMessage(String messageId) async {
    await _client
        .schema('social')
        .from('forum_messages')
        .update({'is_pinned': false}).eq('id', messageId);
  }

  Future<void> submitReport({
    required String targetUserId,
    String? messageId,
    required String reasonId,
    required String description,
  }) async {
    await _client.schema('api').rpc('submit_report', params: {
      'p_target_user_id': targetUserId,
      'p_target_message_id': messageId,
      'p_reason_id': reasonId,
      'p_description': description,
    });
  }

  Future<List<Map<String, dynamic>>> getThreadReplies({
    required String rootMessageId,
    required String rootCreatedAt,
    int limit = 30,
    int offset = 0,
  }) async {
    final data = await _client.schema('api').rpc('get_thread_replies', params: {
      'p_root_id': rootMessageId,
      'p_root_created_at': rootCreatedAt,
      'p_limit': limit,
      'p_offset': offset,
    });
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Map<String, dynamic>>> getMessages({
    required String forumId,
    int limit = 50,
    String? before,
    String? after,
    String? searchQuery,
    String? messageType,
    String? hashtag,
  }) async {
    var query =
        _client.from('vw_forum_messages').select().eq('forum_id', forumId);

    if (messageType != null) {
      query = query.eq('message_type', messageType);
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
