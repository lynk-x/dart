import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

class OptionEditorRow extends StatelessWidget {
  final int index;
  final String text;
  final bool isCorrect;
  final bool isQuiz;
  final ValueChanged<String> onChanged;
  final VoidCallback onToggleCorrect;
  final VoidCallback onRemove;

  const OptionEditorRow({
    super.key,
    required this.index,
    required this.text,
    required this.isCorrect,
    required this.isQuiz,
    required this.onChanged,
    required this.onToggleCorrect,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          if (isQuiz)
            Checkbox(
              value: isCorrect,
              onChanged: (_) => onToggleCorrect(),
              activeColor: context.accentColor,
            ),
          Expanded(
            child: TextFormField(
              initialValue: text,
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Option ${index + 1}',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.white54),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
