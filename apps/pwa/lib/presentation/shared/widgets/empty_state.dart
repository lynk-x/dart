import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

class EmptyState extends StatelessWidget {
  final String message;

  const EmptyState({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.inter(
            fontSize: 16,
            color: Colors.grey[500],
          ),
        ),
      ),
    );
  }
}
