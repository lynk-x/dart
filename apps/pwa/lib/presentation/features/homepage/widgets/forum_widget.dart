import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lynk_core/core.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lynk_x/core/network/lynk_cache_manager.dart';
import 'package:lynk_x/core/utils/image_optimizer.dart';

/// A card widget displaying a forum event summary on the home feed.
///
/// Shows the event [EventModel.thumbnailUrl], [EventModel.title],
/// [EventModel.startDatetime], and an optional unread [EventModel.chatCount] badge.
/// Tapping the card navigates to the Forum screen; the receipt icon navigates to Tickets.
class ForumWidget extends StatelessWidget {
  /// The event to display.
  final EventModel event;

  /// Whether to display in grid mode (square shape, background image).
  final bool isGrid;

  const ForumWidget({
    super.key,
    required this.event,
    this.isGrid = false,
  });

  /// "Today · 3:30 PM", "Tomorrow · 7:00 PM", "In 3 days · 6:00 PM" for
  /// events within the next week; falls back to the absolute date further
  /// out or for events that have already started/passed.
  static String _formatEventDate(DateTime startDatetime) {
    final now = DateTime.now();
    final time = DateFormat('h:mm a').format(startDatetime);

    final startDay = DateTime(startDatetime.year, startDatetime.month, startDatetime.day);
    final today = DateTime(now.year, now.month, now.day);
    final daysUntil = startDay.difference(today).inDays;

    if (daysUntil == 0) return 'Today • $time';
    if (daysUntil == 1) return 'Tomorrow • $time';
    if (daysUntil > 1 && daysUntil <= 7) return 'In $daysUntil days • $time';

    return DateFormat('EEE, MMM d • h:mm a').format(startDatetime);
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = _formatEventDate(event.startDatetime);

    if (isGrid) {
      return FlameBadge(
        showBadge: event.hasUnread,
        content: event.chatCount.toString(),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: event.isPassed
                  ? Colors.white10
                  : context.accentColor.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14.5),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.push(
                    '/forum/${event.forumReference ?? event.reference ?? event.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Fixed Height Poster Image Area
                    SizedBox(
                      height: 180,
                      child: _buildImage(context),
                    ),

                    // Natural Content-Height Solid Editorial Info Dock
                    Container(
                      color: AppColors.surface,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            event.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.interTight(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: event.isPassed
                                  ? Colors.white54
                                  : Colors.white,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 13,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  formattedDate,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.inter(
                                    fontSize: 11,
                                    color:
                                        Colors.white.withValues(alpha: 0.65),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 11,
                                color: context.accentColor,
                              ),
                            ],
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
      );
    }

    return FlameBadge(
      showBadge: event.hasUnread,
      content: event.chatCount.toString(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: event.isPassed
                ? Colors.transparent
                : context.accentColor.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: event.isPassed
              ? null
              : [
                  BoxShadow(
                    color: context.accentColor.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.push('/forum/${event.forumReference ?? event.reference ?? event.id}'),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 54,
                        height: 54,
                        child: _buildImage(context),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.interTight(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: event.isPassed
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formattedDate,
                            style: AppTypography.inter(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.6),
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

  Widget _buildImage(BuildContext context) {
    if (event.thumbnailUrl != null) {
      if (event.thumbnailUrl!.startsWith('assets/')) {
        return Image.asset(
          event.thumbnailUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildPlaceholder(isError: true),
        );
      }
      return CachedNetworkImage(
        imageUrl: ImageOptimizer.getOptimizedUrl(
          event.thumbnailUrl!,
          width: isGrid ? 350 : 120,
          height: isGrid ? 350 : 120,
        ),
        cacheManager: LynkCacheManager.instance,
        memCacheWidth: isGrid ? 350 : 120,
        memCacheHeight: isGrid ? 350 : 120,
        fit: BoxFit.cover,
        placeholder: (_, __) => _buildPlaceholder(),
        errorWidget: (_, __, ___) => _buildPlaceholder(isError: true),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder({bool isError = false}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.tertiary,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Icon(
        isError ? Icons.broken_image : Icons.image,
        color: AppColors.secondaryBackground,
        size: isGrid ? 48 : 30,
      ),
    );
  }
}
