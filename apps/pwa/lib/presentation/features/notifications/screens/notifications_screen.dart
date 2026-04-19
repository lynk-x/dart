import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
        context.push('/wallet');
        break;
      case NotificationType.ticketResaleOffer:
        final listingId = data['listing_id'] as String?;
        if (listingId != null) {
          _showResaleOfferDialog(notification, listingId, data);
        }
        break;
      default:
        break;
    }
  }

  void _showResaleOfferDialog(
    NotificationModel notification,
    String listingId,
    Map<String, dynamic> data,
  ) {
    final currency = data['currency'] as String? ?? '';
    final price = (data['asking_price'] as num?)?.toStringAsFixed(2) ?? '—';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.tertiary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Resale Offer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.body ?? notification.title, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.account_balance_wallet, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text('$currency $price', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Payment will be deducted from your wallet.', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _respondToOffer(listingId, accept: false);
            },
            child: const Text('Decline', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _respondToOffer(listingId, accept: true);
            },
            child: const Text('Accept & Pay', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _respondToOffer(String listingId, {required bool accept}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client.rpc(
        accept ? 'accept_ticket_listing' : 'decline_ticket_listing',
        params: {'p_listing_id': listingId},
      );
      messenger.showSnackBar(SnackBar(
        content: Text(accept ? 'Ticket purchased! Check your tickets.' : 'Offer declined.'),
        backgroundColor: accept ? AppColors.primary : Colors.grey[700],
      ));
      if (accept && mounted) context.push('/tickets');
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: Colors.red,
      ));
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
                  final cubit = context.read<NotificationCubit>();
                  cubit.deleteNotification(notification.id);

                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${notification.title} dismissed'),
                      action: SnackBarAction(
                        label: 'Undo',
                        onPressed: () => cubit.loadNotifications(),
                      ),
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
