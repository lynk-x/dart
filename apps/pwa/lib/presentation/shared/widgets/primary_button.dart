import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

/// A reusable button with a consistent style for the app.
///
/// Displays an [icon] and [text] side-by-side.
class PrimaryButton extends StatelessWidget {
  final IconData? icon;
  final String text;
  final VoidCallback? onPressed;

  const PrimaryButton({
    super.key,
    this.icon,
    required this.text,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: AppDimensions.spacingSm),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.secondaryText,
          padding: EdgeInsets.symmetric(vertical: AppDimensions.spacingMd),
          shape: RoundedRectangleBorder(
            borderRadius: AppDimensions.borderRadiusMd,
          ),
          elevation: 0,
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: AppDimensions.iconMd),
              SizedBox(width: AppDimensions.spacingSm),
            ],
            Text(
              text,
              style: AppTypography.interTight(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
