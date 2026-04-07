import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/notifications/widgets/notification_card.dart';
import 'package:lynk_x/presentation/features/notifications/models/notification_model.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';
import 'package:lynk_x/presentation/features/notifications/cubit/notification_cubit.dart';
import 'package:lynk_x/presentation/features/notifications/cubit/notification_state.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  void _handleNotificationTap(NotificationModel notification) {
    // 1. Mark as read immediately
    context.read<NotificationCubit>().markAsRead(notification.id);

    // 2. Extract deep-link data
    final data = notification.data ?? {};
    final actionUrl = notification.actionUrl;
    final type = notification.type;

    // 3. Smart Navigation
    if (actionUrl != null && actionUrl.startsWith('/')) {
      context.push(actionUrl);
      return;
    }

    switch (type) {
      case NotificationType.mention:
      case NotificationType.announcements:
      case NotificationType.livechats:
      case NotificationType.media:
        final forumId = data['forum_id'] as String?;
        context.push('/forum', extra: forumId);
        break;
      case NotificationType.eventUpdate:
        final eventId = data['event_id'] as String?;
        if (eventId != null) {
          // Navigate to the event's forum (community hub for that event)
          context.push('/forum/$eventId');
        }
        break;
      case NotificationType.moneyIn:
      case NotificationType.moneyOut:
        // Navigate to wallet so user can see the updated balance / transaction
        context.push('/wallet');
        break;
      default:
        // No specific action
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 32, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          BlocBuilder<NotificationCubit, NotificationState>(
            builder: (context, state) {
              final isMarking =
                  state is NotificationLoaded && state.isMarkingAllRead;
              return IconButton(
                icon: isMarking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryText,
                        ),
                      )
                    : const Icon(Icons.done_all,
                        color: AppColors.primaryText, size: 32),
                onPressed: isMarking
                    ? null
                    : () => context.read<NotificationCubit>().markAllAsRead(),
                tooltip: 'Mark all as read',
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<NotificationCubit, NotificationState>(
        builder: (context, state) {
          if (state is NotificationLoading || state is NotificationInitial) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (state is NotificationError) {
            return Center(
              child: Text(
                'Error: ${state.message}',
                style: const TextStyle(color: Colors.white70),
              ),
            );
          }

          final notifications = (state as NotificationLoaded).notifications;

          if (notifications.isEmpty) {
            return const EmptyState(message: 'No notifications yet');
          }

          return ListView.separated(
            padding: const EdgeInsets.only(top: 8, bottom: 20),
            itemCount: notifications.length,
            separatorBuilder: (context, index) => const SizedBox(height: 0),
            itemBuilder: (context, index) {
              final notification = notifications[index];

              return Dismissible(
                key: Key(notification.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20.0),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (direction) {
                  context
                      .read<NotificationCubit>()
                      .deleteNotification(notification.id);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${notification.title} dismissed'),
                    ),
                  );
                },
                child: NotificationCard(
                  model: notification,
                  onTap: () => _handleNotificationTap(notification),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
