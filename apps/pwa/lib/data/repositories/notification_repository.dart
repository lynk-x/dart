import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/presentation/features/notifications/models/notification_model.dart';

class NotificationRepository {
  final SupabaseClient _client;
  NotificationRepository(this._client);

  /// [offset]/[limit] page the result (default: first 30) — previously this
  /// had no range() at all, fetching a user's ENTIRE notification history on
  /// every load. That grows unbounded over time (worse now with the
  /// moderation-category notices added alongside the existing social/wallet
  /// ones) and PostgREST silently truncates past its own default row cap
  /// rather than erroring, so it would eventually just drop older rows with
  /// no signal to the caller.
  Future<List<NotificationModel>> getNotifications({
    String? accountId,
    int offset = 0,
    int limit = 30,
  }) async {
    var query = _client
        .schema('api')
        .from('v1_notifications')
        .select();

    if (accountId != null) {
      query = query.eq('data->>account_id', accountId);
    }

    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List)
        .map((json) => NotificationModel.fromMap(json as Map<String, dynamic>))
        .toList();
  }

  // Marks a single notification as read via RPC rather than a direct view

  Future<void> markAsRead(String id, DateTime createdAt) async {
    await _client
        .schema('api')
        .rpc('mark_notifications_read', params: {'p_notification_ids': [id]});
  }

  Future<void> markAllAsRead(String userId) async {
    await _client.schema('api').rpc('mark_all_notifications_read');
  }

  // Deletes a single notification via RPC rather than a direct view delete

  Future<void> deleteNotification(String id, DateTime createdAt) async {
    await _client
        .schema('api')
        .rpc('bulk_delete_notifications', params: {'p_notification_ids': [id]});
  }

  RealtimeChannel subscribeToNotifications(
    String userId,
    void Function(PostgresChangePayload) callback,
  ) {
    return _client
        .channel('notifications_realtime:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'comms',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: callback,
        );
  }

  void unsubscribe(RealtimeChannel channel) {
    _client.removeChannel(channel);
  }
}
