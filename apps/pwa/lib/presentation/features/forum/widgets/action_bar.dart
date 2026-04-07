import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

/// Represents an individual actionable item within an [ActionBar].
class ActionBarItem {
  /// The text label displayed for this action.
  final String label;

  /// The callback triggered when the action is tapped.
  final VoidCallback onTap;

  /// Optional color override for the action text (e.g., red for 'Delete').
  final Color? color;

  ActionBarItem({
    required this.label,
    required this.onTap,
    this.color,
  });
}

/// A horizontal bar of actionable text items separated by dots.
///
/// Commonly used for message actions (Report, Delete) or user actions (Call, Profile).
class ActionBar extends StatelessWidget {
  final List<ActionBarItem> items;
  final EdgeInsetsGeometry padding;
  final MainAxisAlignment mainAxisAlignment;

  const ActionBar({
    super.key,
    required this.items,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    List<Widget> children = [];
    for (int i = 0; i < items.length; i++) {
      children.add(_buildActionText(items[i]));
      if (i < items.length - 1) {
        children.add(_buildSeparator());
      }
    }

    return Padding(
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: mainAxisAlignment,
        children: children,
      ),
    );
  }

  Widget _buildSeparator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '.',
        style: TextStyle(color: Colors.white24, fontSize: 16),
      ),
    );
  }

  Widget _buildActionText(ActionBarItem item) {
    return GestureDetector(
      onTap: item.onTap,
      child: Text(
        item.label,
        style: AppTypography.inter(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: item.color ?? AppColors.primaryText,
        ),
      ),
    );
  }
}
