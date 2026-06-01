import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lynk_x/data/repositories/repositories.dart';
import 'notification_state.dart';
import 'package:lynk_x/presentation/features/notifications/models/notification_model.dart';

class NotificationCubit extends Cubit<NotificationState> {
  final NotificationRepository _repo;
  NotificationCubit(this._repo) : super(const NotificationInitial());

  RealtimeChannel? _channel;

  /// Returns the current user's ID, or null if auth has not resolved yet.
  String? get _userId {
    return Supabase.instance.client.auth.currentUser?.id;
  }

  Future<void> loadNotifications() async {
    final uid = _userId;
    if (uid == null) return; // Auth not ready — called too early
    emit(const NotificationLoading());
    try {

      final notifications = await _repo.getNotifications();

      emit(NotificationLoaded(notifications: notifications));
      _subscribeToNotifications();
    } catch (e) {
      emit(NotificationError(e.toString()));
    }
  }

  void _subscribeToNotifications() {
    final uid = _userId;
    if (uid == null) return;
    if (_channel != null) {
      _repo.unsubscribe(_channel!);
    }
    _channel = _repo.subscribeToNotifications(uid, _handleRealtimeUpdate)
      ..subscribe();
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

  /// Marks a single notification read. notifications.notifications is partitioned
  /// by created_at with composite PK (id, created_at), so the createdAt must be
  /// in the WHERE clause or the UPDATE matches no rows.
  Future<void> markAsRead(NotificationModel notification) async {
    // Optimistic update — real-time listener confirms; this prevents stale badge
    final currentState = state;
    if (currentState is NotificationLoaded) {
      final updated = currentState.notifications
          .map((n) => n.id == notification.id ? n.copyWith(isRead: true) : n)
          .toList();
      emit(currentState.copyWith(notifications: updated));
    }
    try {
      await _repo.markAsRead(notification.id, notification.createdAt);
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
      // user_id filter is required: without it, RLS prevents the UPDATE from
      // affecting any rows but it would otherwise scan the whole table.
      await _repo.markAllAsRead(uid);

      final updatedList = currentState.notifications
          .map((n) => n.copyWith(isRead: true))
          .toList();
      emit(NotificationLoaded(notifications: updatedList));
    } catch (e) {
      emit(currentState.copyWith(isMarkingAllRead: false));
    }
  }

  Future<void> deleteNotification(NotificationModel notification) async {
    try {
      await _repo.deleteNotification(notification.id, notification.createdAt);
      // Real-time listener will handle the UI update
    } catch (_) {
      // DB delete failed — reload to restore the dismissed item in the UI
      loadNotifications();
    }
  }

  void reset() {
    if (_channel != null) {
      _repo.unsubscribe(_channel!);
      _channel = null;
    }
    emit(const NotificationInitial());
  }

  @override
  Future<void> close() {
    if (_channel != null) {
      _repo.unsubscribe(_channel!);
      _channel = null;
    }
    return super.close();
  }
}
