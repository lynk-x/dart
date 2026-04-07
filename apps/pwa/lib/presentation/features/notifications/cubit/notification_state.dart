import 'package:lynk_x/presentation/features/notifications/models/notification_model.dart';

abstract class NotificationState {
  const NotificationState();
}

class NotificationInitial extends NotificationState {
  const NotificationInitial();
}

class NotificationLoading extends NotificationState {
  const NotificationLoading();
}

class NotificationLoaded extends NotificationState {
  final List<NotificationModel> notifications;
  final bool isMarkingAllRead;

  const NotificationLoaded({
    required this.notifications,
    this.isMarkingAllRead = false,
  });

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  NotificationLoaded copyWith({
    List<NotificationModel>? notifications,
    bool? isMarkingAllRead,
  }) {
    return NotificationLoaded(
      notifications: notifications ?? this.notifications,
      isMarkingAllRead: isMarkingAllRead ?? this.isMarkingAllRead,
    );
  }
}

class NotificationError extends NotificationState {
  final String message;
  const NotificationError(this.message);
}
