import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

class ProfileListTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? textColor;
  final VoidCallback onTap;

  const ProfileListTile({
    super.key,
    required this.title,
    required this.icon,
    this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        title: Text(
          title,
          style: AppTypography.interTight(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor ?? AppColors.secondaryText,
          ),
        ),
        trailing: Icon(
          icon,
          color: textColor ?? AppColors.secondaryText,
        ),
        onTap: onTap,
      ),
    );
  }
}
