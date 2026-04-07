import 'package:flutter/material.dart';
import '../../core.dart';

/// A reusable primary button with consistent Lynk-X styling.
///
/// Supports [isLoading] state, [icon] integration, and token-based dimensions.
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: AppDimensions.spacingSm),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? AppColors.primary,
          foregroundColor: textColor ?? AppColors.secondaryText,
          minimumSize: const Size.fromHeight(50),
          padding: EdgeInsets.symmetric(vertical: AppDimensions.spacingMd),
          shape: RoundedRectangleBorder(
            borderRadius: AppDimensions.borderRadiusMd,
          ),
          elevation: 0,
        ),
        child: isLoading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    textColor ?? AppColors.secondaryText,
                  ),
                ),
              )
            : Row(
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
                      color: textColor ?? AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
