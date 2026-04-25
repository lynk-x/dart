import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

/// A subtle animated indicator showing that another user is currently typing.
class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'someone is typing...',
            style: AppTypography.inter(
              fontSize: 10,
              color: AppColors.primaryText.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}
