import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:lynk_x/presentation/features/notifications/models/notification_model.dart';

/// A card widget displaying a notification summary.
///
/// Features a [model] containing title, body, timestamp, and metadata.
class NotificationCard extends StatelessWidget {
  final NotificationModel model;
  final VoidCallback onTap;

  const NotificationCard({
    super.key,
    required this.model,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isRead = model.isRead;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isRead ? Colors.transparent : AppColors.surface,
          border: const Border(
            bottom: BorderSide(color: Colors.white12, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon section with unread indicator
            Stack(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: model.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: model.color.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    model.icon,
                    color: isRead ? Colors.white60 : model.color,
                    size: 24,
                  ),
                ),
                if (!isRead)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            // Text Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          model.title,
                          style: AppTypography.interTight(
                            fontSize: 16,
                            fontWeight:
                                isRead ? FontWeight.w500 : FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeago.format(model.createdAt, locale: 'en_short'),
                        style: AppTypography.inter(
                          fontSize: 12,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (model.body != null)
                    Text(
                      model.body!,
                      style: AppTypography.inter(
                        fontSize: 14,
                        color: isRead ? Colors.white60 : Colors.white70,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
