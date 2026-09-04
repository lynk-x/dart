import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:lynk_x/presentation/features/notifications/models/notification_model.dart';
import 'package:lynk_x/core/utils/breakpoints.dart';

class NotificationCard extends StatelessWidget {
  final NotificationModel model;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const NotificationCard({
    super.key,
    required this.model,
    required this.onTap,
    this.onDelete,
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
            // Clean Icon section
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isRead 
                    ? Colors.white.withValues(alpha: 0.03) 
                    : Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isRead 
                      ? Colors.white.withValues(alpha: 0.06) 
                      : Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
              child: Icon(
                model.icon,
                color: isRead ? Colors.white38 : Colors.white70,
                size: 22,
              ),
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
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            timeago.format(model.createdAt, locale: 'en_short'),
                            style: AppTypography.inter(
                              fontSize: 12,
                              color: isRead ? Colors.white38 : Colors.white60,
                              fontWeight: isRead ? FontWeight.normal : FontWeight.w500,
                            ),
                          ),
                          if (!isRead) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: context.accentColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
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
                  if (model.actionLabel != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        height: 34,
                        child: ElevatedButton.icon(
                          onPressed: onTap,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.accentColor,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                          label: Text(
                            model.actionLabel!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (Breakpoints.isTablet(context) && onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
          ],
        ),
      ),
    );
  }
}
