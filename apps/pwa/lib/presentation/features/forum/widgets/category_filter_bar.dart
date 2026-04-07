import 'package:flutter/material.dart' hide ChoiceChip;
import 'package:lynk_x/presentation/shared/widgets/choice_chip.dart';

/// A horizontal scrolling bar of category chips for filtering content.
class CategoryFilterBar extends StatelessWidget {
  /// The list of categories to display.
  final List<String> categories;

  /// The currently selected category.
  final String? selectedCategory;

  /// Callback triggered when the selection changes.
  final Function(String?) onSelectionChanged;

  const CategoryFilterBar({
    super.key,
    this.categories = const ['Urgent', 'Activity', 'Q&A', 'Resources', 'Rules'],
    required this.selectedCategory,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == selectedCategory;

          return ChoiceChip(
            label: category,
            selected: isSelected,
            onSelected: (_) => _handleTap(category),
          );
        },
      ),
    );
  }

  void _handleTap(String tappedCategory) {
    if (selectedCategory == tappedCategory) {
      onSelectionChanged(null); // Unselect
    } else {
      onSelectionChanged(tappedCategory); // Select new
    }
  }
}
