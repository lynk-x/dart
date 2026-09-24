import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

/// Shared list-row card: leading icon (with an optional live-status dot),
/// title + status/subtitle line, and a bottom action row (primary button +
/// up to two trailing icon slots). Used wherever a list of "things you can
/// resume/view/manage" needs the same shape — e.g. LiveQuiz's past-quiz
/// list — instead of each screen hand-rolling its own card.
class ListActionCard extends StatelessWidget {
  final IconData leadingIcon;
  final Color leadingIconColor;
  // Small dot badge on the leading icon (e.g. a "live now" indicator).
  final bool showLeadingBadge;
  final Color? leadingBadgeColor;
  final String title;
  final String subtitle;
  final Color? subtitleColor;
  final bool highlighted;
  final IconData primaryIcon;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  // Second action slot — typically a single icon button (e.g. duplicate,
  // preview). Omit for a card with only a primary action.
  final IconData? secondaryIcon;
  final VoidCallback? onSecondary;
  // Third action slot — an overflow menu's items, or omit entirely for a
  // card with no further actions (in which case a disabled placeholder
  // renders instead, keeping the action row's width consistent).
  final List<PopupMenuEntry<void>>? overflowItems;

  const ListActionCard({
    super.key,
    required this.leadingIcon,
    required this.leadingIconColor,
    this.showLeadingBadge = false,
    this.leadingBadgeColor,
    required this.title,
    required this.subtitle,
    this.subtitleColor,
    this.highlighted = false,
    required this.primaryIcon,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryIcon,
    this.onSecondary,
    this.overflowItems,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? context.accentColor.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: leadingIconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(leadingIcon, color: leadingIconColor, size: 22),
                  ),
                  if (showLeadingBadge)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: leadingBadgeColor ?? context.accentColor,
                          border: Border.all(color: AppColors.surface, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.interTight(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.inter(
                        fontSize: 12,
                        fontWeight: subtitleColor != null ? FontWeight.w600 : FontWeight.normal,
                        color: subtitleColor ?? Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    onPressed: onPrimary,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(primaryIcon, size: 15),
                    label: Text(
                      primaryLabel,
                      style: AppTypography.interTight(fontSize: 12.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              if (secondaryIcon != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 38,
                  height: 38,
                  child: OutlinedButton(
                    onPressed: onSecondary,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Icon(secondaryIcon, color: Colors.white70, size: 15),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              SizedBox(
                width: 38,
                height: 38,
                child: overflowItems != null
                    ? PopupMenuButton<void>(
                        tooltip: 'More actions',
                        color: AppColors.surface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        icon: const Icon(Icons.more_horiz, color: Colors.white70, size: 18),
                        itemBuilder: (context) => overflowItems!,
                      )
                    : OutlinedButton(
                        onPressed: null,
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Icon(Icons.more_horiz, color: Colors.white24, size: 18),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
