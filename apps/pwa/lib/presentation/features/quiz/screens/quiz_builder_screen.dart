import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

import '../cubit/quiz_builder_cubit.dart';
import '../cubit/quiz_builder_state.dart';
import '../models/quiz_builder_model.dart';
import '../widgets/builder/question_editor_card.dart';

class QuizBuilderPage extends StatelessWidget {
  final String forumId;

  const QuizBuilderPage({super.key, required this.forumId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          QuizBuilderCubit(repo: quizRepository, forumId: forumId),
      child: const QuizBuilderView(),
    );
  }
}

class QuizBuilderView extends StatefulWidget {
  const QuizBuilderView({super.key});

  @override
  State<QuizBuilderView> createState() => _QuizBuilderViewState();
}

class _QuizBuilderViewState extends State<QuizBuilderView> {
  late final TextEditingController _titleController;
  late final TextEditingController _infoController;

  @override
  void initState() {
    super.initState();
    final draft = context.read<QuizBuilderCubit>().state.draft;
    _titleController = TextEditingController(text: draft.title);
    _infoController = TextEditingController(text: draft.info);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _infoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<QuizBuilderCubit>();

    return BlocConsumer<QuizBuilderCubit, QuizBuilderState>(
      listenWhen: (prev, curr) =>
          prev.error != curr.error || prev.isSuccess != curr.isSuccess,
      listener: (context, state) {
        if (state.error != null) {
          AppSnackBars.showError(context, state.error!);
        } else if (state.isSuccess) {
          AppSnackBars.showSuccess(
              context, 'Quiz ${state.draft.status} successfully!');
          if (state.draft.status == 'published') {
            context.pop();
          }
        }
      },
      builder: (context, state) {
        final draft = state.draft;
        final isQuiz = draft.type == 'quiz';

        return Scaffold(
          backgroundColor: AppColors.primaryBackground,
          appBar: AppBar(
            backgroundColor: AppColors.primaryBackground,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => _handleExit(context),
            ),
            title: RepaintBoundary(
              child: SvgPicture.asset(
                'assets/images/official_lynk-x_combined-logo.svg',
                width: 140,
                fit: BoxFit.contain,
              ),
            ),
            centerTitle: true,
            actions: [
              if (state.isSaving)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                TextButton(
                  onPressed: () => cubit.saveAndPublish(true),
                  child: Text('Publish',
                      style: TextStyle(
                          color: context.accentColor,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isQuiz ? 'Create Quiz' : 'Create Poll',
                            style: AppTypography.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (draft.status == 'published'
                                    ? Colors.greenAccent
                                    : Colors.orangeAccent)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            draft.status.toUpperCase(),
                            style: AppTypography.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: draft.status == 'published'
                                    ? Colors.greenAccent
                                    : Colors.orangeAccent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _titleController,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (val) => cubit.updateSettings(
                          val, _infoController.text, draft.type),
                      decoration: InputDecoration(
                        labelText: 'Title',
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _infoController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 2,
                      onChanged: (val) => cubit.updateSettings(
                          _titleController.text, val, draft.type),
                      decoration: InputDecoration(
                        labelText: 'Description (optional)',
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: draft.questions.length,
                  onReorder: cubit.reorderQuestions,
                  itemBuilder: (context, index) {
                    final q = draft.questions[index];
                    return QuestionEditorCard(
                      key: ValueKey(q.id ?? 'q_$index'),
                      index: index,
                      question: q,
                      isQuiz: isQuiz,
                      onTextChanged: (val) =>
                          cubit.updateQuestionText(index, val),
                      onAddOption: () => cubit.addOption(index),
                      onRemove: () => cubit.removeQuestion(index),
                      onOptionChanged: (oIndex, val) =>
                          cubit.updateOptionText(index, oIndex, val),
                      onRemoveOption: (oIndex) =>
                          cubit.removeOption(index, oIndex),
                      onToggleCorrect: (oIndex) =>
                          cubit.toggleCorrectOption(index, oIndex),
                    );
                  },
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: cubit.addQuestion,
            backgroundColor: context.accentColor,
            icon: const Icon(Icons.add, color: Colors.black),
            label: const Text('Add Question',
                style: TextStyle(color: Colors.black)),
          ),
        );
      },
    );
  }

  bool _hasUnsavedProgress(DraftQuiz draft) {
    return draft.title.trim().isNotEmpty ||
        draft.info.trim().isNotEmpty ||
        draft.questions.any((q) =>
            q.text.trim().isNotEmpty ||
            q.options.any((o) => o.trim().isNotEmpty));
  }

  void _handleExit(BuildContext context) {
    final cubit = context.read<QuizBuilderCubit>();
    if (!_hasUnsavedProgress(cubit.state.draft)) {
      context.pop();
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Unsaved changes',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'You have unsaved progress on this quiz. Save it as a draft before leaving?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.pop();
            },
            child: const Text('Discard',
                style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await cubit.saveAndPublish(false);
              if (context.mounted && cubit.state.error == null) {
                context.pop();
              }
            },
            child: Text('Save Draft',
                style: TextStyle(
                    color: context.accentColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
