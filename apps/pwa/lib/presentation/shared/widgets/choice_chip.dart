import 'package:flutter/material.dart' as m;
import 'package:lynk_core/core.dart';

class ChoiceChip extends m.StatelessWidget {
  final String label;
  final bool selected;
  final m.ValueChanged<bool>? onSelected;

  const ChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
  });

  @override
  m.Widget build(m.BuildContext context) {
    return m.ChoiceChip(
      label: m.Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.tertiary,
      showCheckmark: false, // No icon allowed
      labelStyle: AppTypography.inter(
        fontSize: 14,
        color: selected ? m.Colors.black : m.Colors.white,
        fontWeight: selected ? m.FontWeight.bold : m.FontWeight.normal,
      ),
      shape: m.RoundedRectangleBorder(
        borderRadius: m.BorderRadius.circular(20),
        side: m.BorderSide.none,
      ),
    );
  }
}
