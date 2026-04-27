import 'package:flutter/material.dart' as m;
import 'package:lynk_core/core.dart';

class TextField extends m.StatelessWidget {
  final String label;
  final String? hintText;
  final m.TextEditingController? controller;
  final int maxLines;
  final m.TextInputType keyboardType;
  final m.Widget? suffixIcon;
  final m.Widget? prefixIcon;
  final bool readOnly;
  final bool? enabled;
  final m.VoidCallback? onTap;

  const TextField({
    super.key,
    required this.label,
    this.hintText,
    this.controller,
    this.maxLines = 1,
    this.keyboardType = m.TextInputType.text,
    this.suffixIcon,
    this.prefixIcon,
    this.readOnly = false,
    this.enabled,
    this.onTap,
  });

  @override
  m.Widget build(m.BuildContext context) {
    return m.Column(
      crossAxisAlignment: m.CrossAxisAlignment.start,
      children: [
        m.Text(
          label,
          style: AppTypography.interTight(
            fontSize: 14,
            fontWeight: m.FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        m.SizedBox(height: AppDimensions.spacingSm),
        m.TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          readOnly: readOnly,
          enabled: enabled,
          onTap: onTap,
          style: AppTypography.inter(color: m.Colors.white, fontSize: 16),
          decoration: m.InputDecoration(
            hintText: hintText,
            hintStyle: AppTypography.inter(
              color: m.Colors.white24,
              fontSize: 16,
            ),
            filled: true,
            fillColor: AppColors.tertiary.withValues(alpha: 0.5),
            contentPadding: m.EdgeInsets.symmetric(
              horizontal: AppDimensions.spacingLg,
              vertical: AppDimensions.spacingLg,
            ),
            border: m.OutlineInputBorder(
              borderRadius: AppDimensions.borderRadiusLg,
              borderSide: m.BorderSide.none,
            ),
            enabledBorder: m.OutlineInputBorder(
              borderRadius: AppDimensions.borderRadiusLg,
              borderSide: m.BorderSide.none,
            ),
            focusedBorder: m.OutlineInputBorder(
              borderRadius: AppDimensions.borderRadiusLg,
              borderSide: const m.BorderSide(
                color: AppColors.primary,
                width: 1,
              ),
            ),
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}
