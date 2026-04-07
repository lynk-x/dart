import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'dart:math' as math;

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

    final badge = Transform.rotate(
      angle: 10 * math.pi / 180, // Tilted container
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Colors.deepOrange,
              Colors.red,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(2), // Sharp flame tip
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
          border: Border.all(
            color: AppColors.primaryBackground,
            width: 2,
          ),
        ),
        // Counter-rotate text so it stays upright
        child: Transform.rotate(
          angle: -10 * math.pi / 180,
          child: Text(
            content,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
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
