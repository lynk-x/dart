import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lynk_core/core.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// A card widget displaying a forum event summary on the home feed.
///
/// Shows the event [EventModel.thumbnailUrl], [EventModel.title],
/// [EventModel.startDatetime], and an optional unread [EventModel.chatCount] badge.
/// Tapping the card navigates to the Forum screen; the receipt icon navigates to Tickets.
class ForumWidget extends StatelessWidget {
  /// The event to display.
  final EventModel event;

  const ForumWidget({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final formattedDate =
        DateFormat('dd/MM/yyyy • h:mm a').format(event.startDatetime);

    return FlameBadge(
      showBadge: event.hasUnread,
      content: event.chatCount.toString(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primaryBackground, width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.push('/forum/${event.id}'),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
            children: [
              // Thumbnail — uses CachedNetworkImage if URL is available,
              // falls back to an icon placeholder for development mock data.
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: event.thumbnailUrl != null
                      ? CachedNetworkImage(
                          imageUrl: event.thumbnailUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: AppColors.secondaryBackground,
                            child: const Icon(
                              Icons.image,
                              color: AppColors.tertiary,
                              size: 30,
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: AppColors.secondaryBackground,
                            child: const Icon(
                              Icons.broken_image,
                              color: AppColors.tertiary,
                              size: 30,
                            ),
                          ),
                        )
                      : Container(
                          color: AppColors.secondaryBackground,
                          child: const Icon(
                            Icons.image,
                            color: AppColors.tertiary,
                            size: 30,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.interTight(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondaryText,
                      ).copyWith(
                        decoration:
                            event.isPassed ? TextDecoration.lineThrough : null,
                        decorationColor:
                            event.isPassed ? AppColors.primaryText : null,
                      ),
                    ),
                    Text(
                      formattedDate,
                      style: AppTypography.inter(
                        fontSize: 14,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
