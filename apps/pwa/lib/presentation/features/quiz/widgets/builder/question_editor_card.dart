import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import '../../models/quiz_builder_model.dart';
import 'option_editor_row.dart';

class QuestionEditorCard extends StatelessWidget {
  final int index;
  final DraftQuestion question;
  final bool isQuiz;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onAddOption;
  final VoidCallback onRemove;
  final void Function(int optionIndex, String text) onOptionChanged;
  final void Function(int optionIndex) onRemoveOption;
  final void Function(int optionIndex) onToggleCorrect;

  const QuestionEditorCard({
    super.key,
    required this.index,
    required this.question,
    required this.isQuiz,
    required this.onTextChanged,
    required this.onAddOption,
    required this.onRemove,
    required this.onOptionChanged,
    required this.onRemoveOption,
    required this.onToggleCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Question ${index + 1}',
                style: AppTypography.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.drag_indicator, color: Colors.white24),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: onRemove,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: question.text,
            onChanged: onTextChanged,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter your question here...',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (isQuiz)
            Text(
              'Options (check to mark as correct)',
              style: AppTypography.inter(fontSize: 12, color: Colors.white54),
            )
          else
            Text(
              'Options',
              style: AppTypography.inter(fontSize: 12, color: Colors.white54),
            ),
          const SizedBox(height: 8),
          ...List.generate(
            question.options.length,
            (oIndex) => OptionEditorRow(
              index: oIndex,
              text: question.options[oIndex],
              isCorrect: question.correctIndices.contains(oIndex),
              isQuiz: isQuiz,
              onChanged: (val) => onOptionChanged(oIndex, val),
              onRemove: () => onRemoveOption(oIndex),
              onToggleCorrect: () => onToggleCorrect(oIndex),
            ),
          ),
          TextButton.icon(
            onPressed: onAddOption,
            icon: const Icon(Icons.add),
            label: const Text('Add Option'),
            style: TextButton.styleFrom(foregroundColor: context.accentColor),
          ),
        ],
      ),
    );
  }
}
