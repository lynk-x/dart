import 'package:material_ui/material_ui.dart' as m;
import 'package:lynk_core/core.dart';

class TextField extends m.StatelessWidget {
  final String label;
  final String? hintText;
  final String? errorText;
  final String? prefixText;
  final m.TextEditingController? controller;
  final int maxLines;
  final m.TextInputType keyboardType;
  final m.Widget? suffixIcon;
  final m.Widget? prefixIcon;
  final bool readOnly;
  final bool? enabled;
  final m.VoidCallback? onTap;
  final m.ValueChanged<String>? onChanged;
  final bool autofocus;

  const TextField({
    super.key,
    required this.label,
    this.hintText,
    this.errorText,
    this.prefixText,
    this.controller,
    this.maxLines = 1,
    this.keyboardType = m.TextInputType.text,
    this.suffixIcon,
    this.prefixIcon,
    this.readOnly = false,
    this.enabled,
    this.onTap,
    this.onChanged,
    this.autofocus = false,
  });

  @override
  m.Widget build(m.BuildContext context) {
    final hasError = errorText != null && errorText!.isNotEmpty;
    return m.Column(
      crossAxisAlignment: m.CrossAxisAlignment.start,
      children: [
        if (hasError) ...[
          m.Text(
            errorText!,
            style: AppTypography.interTight(
              fontSize: 12,
              fontWeight: m.FontWeight.w500,
              color: m.Colors.redAccent,
            ),
          ),
          m.SizedBox(height: AppDimensions.spacingXs),
        ],
        m.Text(
          label,
          style: AppTypography.interTight(
            fontSize: 14,
            fontWeight: m.FontWeight.w600,
            color: context.accentColor,
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
          onChanged: onChanged,
          autofocus: autofocus,
          style: AppTypography.inter(color: m.Colors.white, fontSize: 16),
          decoration: m.InputDecoration(
            hintText: hintText,
            hintStyle: AppTypography.inter(
              color: m.Colors.white24,
              fontSize: 16,
            ),
            prefixText: prefixText,
            prefixStyle: m.TextStyle(color: m.Colors.white54),
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
              borderSide: m.BorderSide(
                color: hasError ? m.Colors.redAccent : context.accentColor,
                width: 1,
              ),
            ),
            errorBorder: m.OutlineInputBorder(
              borderRadius: AppDimensions.borderRadiusLg,
              borderSide: m.BorderSide(
                color: m.Colors.redAccent,
                width: 1,
              ),
            ),
            focusedErrorBorder: m.OutlineInputBorder(
              borderRadius: AppDimensions.borderRadiusLg,
              borderSide: m.BorderSide(
                color: m.Colors.redAccent,
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
