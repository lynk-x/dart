import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_core/core.dart';

import 'package:lynk_x/data/repositories/repositories.dart';
import 'notification_state.dart';
import 'package:lynk_x/presentation/features/notifications/models/notification_model.dart';

/// Owns the notification inbox — paginated load, realtime broadcast sync,
/// and read/delete actions with optimistic updates.
class NotificationCubit extends Cubit<NotificationState> {
  final NotificationRepository _repo;
  final AccountRepository _accountRepo;
  NotificationCubit(this._repo, this._accountRepo) : super(const NotificationInitial());

  static const int _pageSize = 30;

  RealtimeChannel? _channel;

  /// Cached per cubit instance (effectively per session) — this doesn't
  /// change without a re-login, so there's no need to re-resolve it on
  /// every loadNotifications() call.
  String? _resolvedAccountId;

  /// Returns the current user's ID, or null if auth has not resolved yet.
  String? get _userId {
    return Supabase.instance.client.auth.currentUser?.id;
  }

  Future<void> loadNotifications() async {
    final uid = _userId;
    if (uid == null) return; // Auth not ready — called too early
    emit(const NotificationLoading());
    try {
      _resolvedAccountId ??= await _accountRepo.resolveOwnerAccountId(uid);

      final notifications = await _repo.getNotifications(
        accountId: _resolvedAccountId,
        limit: _pageSize,
      );

      emit(NotificationLoaded(
        notifications: notifications,
        hasMore: notifications.length == _pageSize,
      ));
      _subscribeToNotifications();
    } catch (e) {
      emit(NotificationError(e.toFriendlyMessage()));
    }
  }

  /// Fetches the next page and appends it. The initial page comes from
  /// [loadNotifications] above.
  Future<void> loadMore() async {
    final currentState = state;
    if (currentState is! NotificationLoaded) return;
    if (currentState.isLoadingMore || !currentState.hasMore) return;

    final uid = _userId;
    if (uid == null) return;

    emit(currentState.copyWith(isLoadingMore: true));
    try {
      final nextPage = await _repo.getNotifications(
        accountId: _resolvedAccountId,
        offset: currentState.notifications.length,
        limit: _pageSize,
      );

      if (isClosed) return;
      emit(currentState.copyWith(
        notifications: [...currentState.notifications, ...nextPage],
        isLoadingMore: false,
        hasMore: nextPage.length == _pageSize,
      ));
    } catch (_) {
      if (!isClosed) emit(currentState.copyWith(isLoadingMore: false));
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

  /// [payload] comes from Realtime Broadcast from Database
  /// (internal.fn_broadcast_notification_change), not Postgres Changes —
  /// shaped { operation, record, old_record, ... }. Unlike Postgres
  /// Changes' DELETE event (whose old_record RLS truncates to PK-only
  /// columns once the row is already gone), broadcast_changes() reads OLD
  /// directly inside the trigger before RLS ever applies, so old_record is
  /// always the full row here.
  void _handleRealtimeUpdate(Map<String, dynamic> payload) {
    final currentState = state;
    if (currentState is! NotificationLoaded) return;

    final operation = payload['operation'] as String?;
    final record = payload['record'] as Map<String, dynamic>?;
    final oldRecord = payload['old_record'] as Map<String, dynamic>?;

    final List<NotificationModel> updatedList =
        List.from(currentState.notifications);

    if (operation == 'INSERT' && record != null) {
      updatedList.insert(0, NotificationModel.fromMap(record));
    } else if (operation == 'UPDATE' && record != null) {
      final index = updatedList.indexWhere((n) => n.id == record['id']);
      if (index != -1) {
        updatedList[index] = NotificationModel.fromMap(record);
      }
    } else if (operation == 'DELETE' && oldRecord != null) {
      updatedList.removeWhere((n) => n.id == oldRecord['id']);
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
    // Optimistic removal rather than relying on the realtime DELETE event:
    // Supabase Realtime truncates a DELETE's old_record to PK-only columns
    // when RLS is enabled, so a user-initiated delete shouldn't depend on
    // realtime delivery to update the UI.
    final currentState = state;
    List<NotificationModel>? previous;
    if (currentState is NotificationLoaded) {
      previous = currentState.notifications;
      final updated = previous.where((n) => n.id != notification.id).toList();
      emit(currentState.copyWith(notifications: updated));
    }
    try {
      await _repo.deleteNotification(notification.id, notification.createdAt);
    } catch (_) {
      // DB delete failed — restore the optimistically-removed item.
      if (previous != null && !isClosed) {
        emit(NotificationLoaded(notifications: previous));
      } else {
        loadNotifications();
      }
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
