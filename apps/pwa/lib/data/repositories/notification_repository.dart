import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/presentation/features/notifications/models/notification_model.dart';

class NotificationRepository {
  final SupabaseClient _client;
  NotificationRepository(this._client);

  Future<List<NotificationModel>> getNotifications() async {
    final data = await _client
        .schema('api')
        .from('v1_notifications')
        .select()
        .order('created_at', ascending: false);
    return (data as List)
        .map((json) => NotificationModel.fromMap(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> markAsRead(String id, DateTime createdAt) async {
    await _client
        .schema('comms')
        .from('notifications')
        .update({'is_read': true})
        .eq('id', id)
        .eq('created_at', createdAt.toIso8601String());
  }

  Future<void> markAllAsRead(String userId) async {
    await _client.rpc('mark_all_notifications_read');
  }

  Future<void> deleteNotification(String id, DateTime createdAt) async {
    await _client
        .schema('comms')
        .from('notifications')
        .delete()
        .eq('id', id)
        .eq('created_at', createdAt.toIso8601String());
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
