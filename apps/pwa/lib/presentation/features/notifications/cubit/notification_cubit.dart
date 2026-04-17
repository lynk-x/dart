import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_state.dart';
import 'package:lynk_x/presentation/features/notifications/models/notification_model.dart';

class NotificationCubit extends Cubit<NotificationState> {
  NotificationCubit() : super(const NotificationInitial());

  RealtimeChannel? _channel;

  /// Returns the current user's ID, or null if auth has not resolved yet.
  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  Future<void> loadNotifications() async {
    final uid = _userId;
    if (uid == null) return; // Auth not ready — called too early
    emit(const NotificationLoading());
    try {
      final data = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('user_id', uid)
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
    final uid = _userId;
    if (uid == null) return;
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('public:notifications:user=$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
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
    // Optimistic update — real-time listener confirms; this prevents stale badge
    final currentState = state;
    if (currentState is NotificationLoaded) {
      final updated = currentState.notifications
          .map((n) => n.id == notificationId ? n.copyWith(isRead: true) : n)
          .toList();
      emit(currentState.copyWith(notifications: updated));
    }
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true}).eq('id', notificationId);
    } catch (_) {
      // Best-effort — next load will reconcile
    }
  }

  Future<void> markAllAsRead() async {
    final currentState = state;
    if (currentState is! NotificationLoaded) return;

    emit(currentState.copyWith(isMarkingAllRead: true));
    try {
      final uid = _userId;
      if (uid == null) return;
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', uid)
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
    } catch (_) {
      // DB delete failed — reload to restore the dismissed item in the UI
      loadNotifications();
    }
  }

  @override
  Future<void> close() {
    _channel?.unsubscribe();
    return super.close();
  }
}
