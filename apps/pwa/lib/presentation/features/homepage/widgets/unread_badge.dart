import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'unread_badge_text.dart';

/// The unread count shown at the trailing edge of a forum card on the home list.
///
/// A pill in the accent color (it grows with the text, so "42" and "99+" fit) rather than the old
/// floating circle, which overlapped the card edge and let "99+" spill out of its shape. Text
/// color follows the accent's brightness so contrast holds if the accent changes. Renders nothing
/// for a count of zero.
class UnreadBadge extends StatelessWidget {
  final int count;
  const UnreadBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final background = context.accentColor;
    final foreground = ThemeData.estimateBrightnessForColor(background) == Brightness.light
        ? Colors.black
        : Colors.white;
    final text = unreadBadgeText(count);

    return Semantics(
      label: count == 1 ? '1 unread message' : '$text unread messages',
      excludeSemantics: true,
      // Sized by its content (never `Container(alignment: ...)`, which expands to fill any bounded
      // space): the 22 px height is the text's line height, and the width is the text plus padding,
      // at least 22.
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 8),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: AppTypography.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: foreground,
              ).copyWith(height: 2.0, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ),
      ),
    );
  }
}
