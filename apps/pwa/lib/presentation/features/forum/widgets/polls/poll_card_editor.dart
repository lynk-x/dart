import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import 'package:lynk_x/presentation/features/quiz/cubit/quiz_builder_cubit.dart';
import 'package:lynk_x/presentation/features/quiz/cubit/quiz_builder_state.dart';
import 'package:lynk_x/presentation/features/quiz/models/quiz_builder_model.dart';

/// Composer-facing poll editor, styled as the same solid-green card
/// [PollCard] uses to render a published poll — the thing you're building
/// looks exactly like the thing people will vote on. Polls are single
/// question only (unlike quizzes, which stay multi-question via
/// QuizBuilderPage); this reuses QuizBuilderCubit/DraftQuiz for the actual
/// save/publish plumbing rather than duplicating it.
class PollCardEditor extends StatelessWidget {
  final String forumId;
  final VoidCallback? onCancel;
  final VoidCallback? onPublished;

  const PollCardEditor({
    super.key,
    required this.forumId,
    this.onCancel,
    this.onPublished,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => QuizBuilderCubit(repo: quizRepository, forumId: forumId)
        ..addQuestion(),
      child: _PollCardEditorView(onCancel: onCancel, onPublished: onPublished),
    );
  }
}

class _PollCardEditorView extends StatefulWidget {
  final VoidCallback? onCancel;
  final VoidCallback? onPublished;

  const _PollCardEditorView({this.onCancel, this.onPublished});

  @override
  State<_PollCardEditorView> createState() => _PollCardEditorViewState();
}

class _PollCardEditorViewState extends State<_PollCardEditorView> {
  late final TextEditingController _questionController;
  late List<TextEditingController> _optionControllers;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController();
    _optionControllers = [TextEditingController(), TextEditingController()];
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncOptionControllers(List<String> options) {
    // Keep controller count in sync with draft option count (add/remove),
    // without clobbering text the user is actively typing in existing ones.
    while (_optionControllers.length < options.length) {
      _optionControllers.add(TextEditingController(text: options[_optionControllers.length]));
    }
    while (_optionControllers.length > options.length) {
      _optionControllers.removeLast().dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<QuizBuilderCubit>();

    return BlocConsumer<QuizBuilderCubit, QuizBuilderState>(
      listenWhen: (prev, curr) => prev.error != curr.error || prev.isSuccess != curr.isSuccess,
      listener: (context, state) {
        if (state.error != null) {
          AppSnackBars.showError(context, state.error!);
        } else if (state.isSuccess) {
          AppSnackBars.showSuccess(context, 'Poll posted!');
          widget.onPublished?.call();
        }
      },
      builder: (context, state) {
        final DraftQuestion question =
            state.draft.questions.isNotEmpty ? state.draft.questions.first : const DraftQuestion();
        _syncOptionControllers(question.options);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF20F928),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.poll_outlined, color: Colors.black, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Poll',
                    style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: widget.onCancel,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Question
              _EditorField(
                controller: _questionController,
                hint: 'Ask a question…',
                onChanged: (val) => cubit.updateQuestionText(0, val),
                bold: true,
                fontSize: 15,
              ),
              const SizedBox(height: 10),

              // Options
              ...question.options.asMap().entries.map((entry) {
                final i = entry.key;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _EditorField(
                          controller: _optionControllers[i],
                          hint: 'Option ${i + 1}',
                          onChanged: (val) => cubit.updateOptionText(0, i, val),
                          fontSize: 14,
                          filled: true,
                        ),
                      ),
                      if (question.options.length > 2)
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.black54, size: 20),
                          onPressed: () => cubit.removeOption(0, i),
                        ),
                    ],
                  ),
                );
              }),

              // Add option
              if (question.options.length < 6)
                TextButton.icon(
                  onPressed: () => cubit.addOption(0),
                  icon: const Icon(Icons.add, color: Colors.black, size: 18),
                  label: const Text('Add option', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    alignment: Alignment.centerLeft,
                  ),
                ),

              const SizedBox(height: 12),

              // Publish
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: state.isSaving
                      ? null
                      : () {
                          cubit.updateSettings(
                            _questionController.text.trim().isEmpty
                                ? 'Poll'
                                : _questionController.text.trim(),
                            '',
                            'poll',
                          );
                          cubit.saveAndPublish(true);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: state.isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Post Poll', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EditorField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool bold;
  final bool filled;
  final double fontSize;

  const _EditorField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.bold = false,
    this.filled = false,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: filled
          ? BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))
          : null,
      padding: filled ? const EdgeInsets.symmetric(horizontal: 12) : EdgeInsets.zero,
      height: filled ? 42 : null,
      alignment: filled ? Alignment.centerLeft : null,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: filled ? 1 : null,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.4), fontWeight: FontWeight.normal),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
