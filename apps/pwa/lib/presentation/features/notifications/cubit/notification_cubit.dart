import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_state.dart';
import 'package:lynk_x/presentation/features/notifications/models/notification_model.dart';

class NotificationCubit extends Cubit<NotificationState> {
  NotificationCubit() : super(const NotificationInitial());

  RealtimeChannel? _channel;
  String get userId => Supabase.instance.client.auth.currentUser!.id;

  Future<void> loadNotifications() async {
    emit(const NotificationLoading());
    try {
      final data = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final notifications = (data as List)
          .map((json) => NotificationModel.fromMap(json))
          .toList();

      emit(NotificationLoaded(notifications: notifications));
      _subscribeToNotifications();
    } catch (e) {
      emit(NotificationError(e.toString()));
    }
  }

  void _subscribeToNotifications() {
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('public:notifications:user=$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          // Use filter to only get changes for the current user
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            _handleRealtimeUpdate(payload);
          },
        )
        .subscribe();
  }

  void _handleRealtimeUpdate(PostgresChangePayload payload) {
    final currentState = state;
    if (currentState is! NotificationLoaded) return;

    final List<NotificationModel> updatedList =
        List.from(currentState.notifications);

    if (payload.eventType == PostgresChangeEvent.insert) {
      updatedList.insert(0, NotificationModel.fromMap(payload.newRecord));
    } else if (payload.eventType == PostgresChangeEvent.update) {
      final index =
          updatedList.indexWhere((n) => n.id == payload.newRecord['id']);
      if (index != -1) {
        updatedList[index] = NotificationModel.fromMap(payload.newRecord);
      }
    } else if (payload.eventType == PostgresChangeEvent.delete) {
      updatedList.removeWhere((n) => n.id == payload.oldRecord['id']);
    }

    emit(currentState.copyWith(notifications: updatedList));
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true}).eq('id', notificationId);
      // Real-time listener will handle the UI update
    } catch (_) {}
  }

  Future<void> markAllAsRead() async {
    final currentState = state;
    if (currentState is! NotificationLoaded) return;

    emit(currentState.copyWith(isMarkingAllRead: true));
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);

      final updatedList = currentState.notifications
          .map((n) => n.copyWith(isRead: true))
          .toList();
      emit(NotificationLoaded(notifications: updatedList));
    } catch (e) {
      emit(currentState.copyWith(isMarkingAllRead: false));
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    try {
      await Supabase.instance.client
          .from('notifications')
          .delete()
          .eq('id', notificationId);
      // Real-time listener will handle the UI update
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _channel?.unsubscribe();
    return super.close();
  }
}
