import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

class PermissionRequestSheet extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onGranted;

  const PermissionRequestSheet({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.actionLabel = 'Continue',
    required this.onGranted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 40),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: AppTypography.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: AppTypography.inter(
              fontSize: 14,
              color: Colors.white70,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          PrimaryButton(
            text: actionLabel,
            onPressed: () {
              Navigator.pop(context);
              onGranted();
            },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Not now',
              style: AppTypography.inter(
                color: Colors.white38,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
