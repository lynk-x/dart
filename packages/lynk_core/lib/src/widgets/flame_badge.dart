import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

class FlameBadge extends StatelessWidget {
  final Widget? child;
  final String content;
  final bool showBadge;

  const FlameBadge({
    super.key,
    this.child,
    required this.content,
    this.showBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!showBadge) {
      return child ?? const SizedBox.shrink();
    }

    final badge = Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.primaryBackground,
          width: 2,
        ),
      ),
      child: Text(
        content,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    if (child != null) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          child!,
          Positioned(
            top: -8,
            right: -8,
            child: badge,
          ),
        ],
      );
    }

    return badge;
  }
}
