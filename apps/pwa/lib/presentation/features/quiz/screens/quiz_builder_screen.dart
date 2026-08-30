import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

import '../cubit/quiz_builder_cubit.dart';
import '../cubit/quiz_builder_state.dart';
import '../models/quiz_builder_model.dart';
import '../widgets/builder/option_editor_row.dart';

/// Entry page for building a LiveQuiz or Poll using a Master-Detail Slide Canvas layout.
class QuizBuilderPage extends StatelessWidget {
  final String forumId;
  final String? channelId;
  final String? channelCreatedAt;
  final String messageType;

  const QuizBuilderPage({
    super.key,
    required this.forumId,
    this.channelId,
    this.channelCreatedAt,
    required this.messageType,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => QuizBuilderCubit(
        repo: quizRepository,
        forumId: forumId,
        channelId: channelId,
        channelCreatedAt: channelCreatedAt,
      )..addQuestion(),
      child: QuizBuilderView(messageType: messageType),
    );
  }
}

class QuizBuilderView extends StatefulWidget {
  final String messageType;

  const QuizBuilderView({super.key, required this.messageType});

  @override
  State<QuizBuilderView> createState() => _QuizBuilderViewState();
}

class _QuizBuilderViewState extends State<QuizBuilderView> {
  late final TextEditingController _titleController;
  late final TextEditingController _infoController;
  int _activeQuestionIndex = 0;

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
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return BlocConsumer<QuizBuilderCubit, QuizBuilderState>(
      listenWhen: (prev, curr) =>
          prev.error != curr.error || prev.isSuccess != curr.isSuccess,
      listener: (context, state) {
        if (state.error != null) {
          AppSnackBars.showError(context, state.error!);
        } else if (state.isSuccess) {
          AppSnackBars.showSuccess(context, 'Quiz published successfully!');
          context.pop({
            'messageId': state.createdMessageId,
            'createdAt': state.createdMessageCreatedAt,
            'title': state.draft.title,
          });
        }
      },
      builder: (context, state) {
        final draft = state.draft;
        final isQuiz = draft.type == 'quiz';
        final totalQuestions = draft.questions.length;

        // Ensure active index is bounded
        if (_activeQuestionIndex >= totalQuestions && totalQuestions > 0) {
          _activeQuestionIndex = totalQuestions - 1;
        }

        return Scaffold(
          backgroundColor: AppColors.primaryBackground,
          appBar: AppBar(
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => _handleExit(context),
            ),
            title: Text(
              isQuiz ? 'LiveQuiz' : 'Poll',
              style: AppTypography.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            centerTitle: false,
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
                IconButton(
                  icon: Icon(Icons.check_rounded, color: context.accentColor),
                  tooltip: 'Publish',
                  onPressed: () => cubit.publish(widget.messageType),
                ),
            ],
          ),
          body: isDesktop
              ? _buildDesktopCanvas(context, state, cubit, isQuiz)
              : _buildMobileCanvas(context, state, cubit, isQuiz),
        );
      },
    );
  }

  /// Desktop 2-Column Canvas: Left Slide Dock + Center Stage Editor
  Widget _buildDesktopCanvas(
    BuildContext context,
    QuizBuilderState state,
    QuizBuilderCubit cubit,
    bool isQuiz,
  ) {
    final draft = state.draft;
    final activeQuestion = draft.questions.isNotEmpty
        ? draft.questions[_activeQuestionIndex]
        : null;

    return Row(
      children: [
        // Left Column: Question Slide Deck Thumbnails
        SizedBox(
          width: 260,
          child: _SlideDeckLeftPanel(
            draft: draft,
            activeQuestionIndex: _activeQuestionIndex,
            onSelectQuestion: (index) {
              setState(() => _activeQuestionIndex = index);
            },
            onAddQuestion: () {
              cubit.addQuestion();
              setState(() {
                _activeQuestionIndex = draft.questions.length;
              });
            },
            onRemoveQuestion: (index) {
              cubit.removeQuestion(index);
              if (_activeQuestionIndex >= draft.questions.length - 1 && _activeQuestionIndex > 0) {
                setState(() => _activeQuestionIndex--);
              }
            },
            onReorder: (oldIndex, newIndex) {
              cubit.reorderQuestions(oldIndex, newIndex);
              setState(() {
                if (_activeQuestionIndex == oldIndex) {
                  _activeQuestionIndex = newIndex;
                } else if (oldIndex < _activeQuestionIndex && newIndex >= _activeQuestionIndex) {
                  _activeQuestionIndex--;
                } else if (oldIndex > _activeQuestionIndex && newIndex <= _activeQuestionIndex) {
                  _activeQuestionIndex++;
                }
              });
            },
            onOpenSettings: () => _showSettingsBottomSheet(context, cubit, draft),
          ),
        ),
        const VerticalDivider(width: 1, color: Colors.white10),

        // Center Stage: Focused Active Question Canvas
        Expanded(
          child: Container(
            color: AppColors.primaryBackground,
            padding: const EdgeInsets.all(24),
            child: activeQuestion == null
                ? const Center(child: Text('No questions added.', style: TextStyle(color: Colors.white54)))
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: KeyedSubtree(
                      key: ValueKey('stage_q_$_activeQuestionIndex'),
                      child: _QuestionStageEditor(
                        index: _activeQuestionIndex,
                        totalQuestions: draft.questions.length,
                        question: activeQuestion,
                        isQuiz: isQuiz,
                        cubit: cubit,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// Mobile PWA Layout: Focused Stage + Bottom Slide Deck Carousel Dock
  Widget _buildMobileCanvas(
    BuildContext context,
    QuizBuilderState state,
    QuizBuilderCubit cubit,
    bool isQuiz,
  ) {
    final draft = state.draft;
    final activeQuestion = draft.questions.isNotEmpty
        ? draft.questions[_activeQuestionIndex]
        : null;

    return Column(
      children: [
        // Top Collapsible Title Strip
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _titleController,
            style: AppTypography.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            onChanged: (val) => cubit.updateSettings(val, _infoController.text, draft.type),
            decoration: const InputDecoration(
              hintText: 'Quiz Title...',
              hintStyle: TextStyle(color: Colors.white38),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        const Divider(height: 1, color: Colors.white10),

        // Center Stage Editor
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: activeQuestion == null
                ? const Center(child: Text('No questions added.', style: TextStyle(color: Colors.white54)))
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: KeyedSubtree(
                      key: ValueKey('mobile_q_$_activeQuestionIndex'),
                      child: _QuestionStageEditor(
                        index: _activeQuestionIndex,
                        totalQuestions: draft.questions.length,
                        question: activeQuestion,
                        isQuiz: isQuiz,
                        cubit: cubit,
                      ),
                    ),
                  ),
          ),
        ),

        // Bottom Slide Dock Carousel
        _MobileBottomSlideDock(
          draft: draft,
          activeQuestionIndex: _activeQuestionIndex,
          onSelectQuestion: (index) {
            setState(() => _activeQuestionIndex = index);
          },
          onAddQuestion: () {
            cubit.addQuestion();
            setState(() {
              _activeQuestionIndex = draft.questions.length;
            });
          },
          onRemoveQuestion: (index) {
            cubit.removeQuestion(index);
            if (_activeQuestionIndex >= draft.questions.length - 1 && _activeQuestionIndex > 0) {
              setState(() => _activeQuestionIndex--);
            }
          },
          onOpenSettings: () => _showSettingsBottomSheet(context, cubit, draft),
        ),
      ],
    );
  }

  void _showSettingsBottomSheet(BuildContext context, QuizBuilderCubit cubit, DraftQuiz draft) {
    final isQuiz = draft.type == 'quiz';
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Quiz Settings',
                    style: AppTypography.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _HeaderInputSection(
                titleController: _titleController,
                infoController: _infoController,
                draft: draft,
                cubit: cubit,
              ),
              if (isQuiz) ...[
                const SizedBox(height: 16),
                _GameSettingsSection(draft: draft, cubit: cubit),
              ],
            ],
          ),
        ),
      ),
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
        title: const Text('Discard quiz?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'You have unsaved progress on this quiz. It will be lost if you leave now.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.pop();
            },
            child: const Text('Discard', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

/// Left Panel Slide Deck for Desktop Screens
class _SlideDeckLeftPanel extends StatelessWidget {
  final DraftQuiz draft;
  final int activeQuestionIndex;
  final ValueChanged<int> onSelectQuestion;
  final VoidCallback onAddQuestion;
  final ValueChanged<int> onRemoveQuestion;
  final ReorderCallback onReorder;
  final VoidCallback onOpenSettings;

  const _SlideDeckLeftPanel({
    required this.draft,
    required this.activeQuestionIndex,
    required this.onSelectQuestion,
    required this.onAddQuestion,
    required this.onRemoveQuestion,
    required this.onReorder,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Questions (${draft.questions.length})',
                  style: AppTypography.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.add_circle, color: context.accentColor),
                      tooltip: 'Add Question',
                      onPressed: onAddQuestion,
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune, color: Colors.white70),
                      tooltip: 'Settings',
                      onPressed: onOpenSettings,
                    ),
                  ],                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: draft.questions.length,
              // ignore: deprecated_member_use
              onReorder: (oldIndex, newIndex) {
                var targetIndex = newIndex;
                if (targetIndex > oldIndex) targetIndex -= 1;
                onReorder(oldIndex, targetIndex);
              },
              itemBuilder: (context, index) {
                final q = draft.questions[index];
                final isSelected = index == activeQuestionIndex;
                final String titleSnippet = q.text.trim().isEmpty
                    ? 'Untitled Question'
                    : q.text.trim();

                return InkWell(
                  key: ValueKey('left_slide_$index'),
                  onTap: () => onSelectQuestion(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? context.accentColor.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? context.accentColor : Colors.white10,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected ? context.accentColor : Colors.white12,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titleSnippet,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.inter(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? Colors.white : Colors.white70,
                                ),
                              ),
                              Text(
                                '${q.options.length} options',
                                style: const TextStyle(fontSize: 10, color: Colors.white38),
                              ),
                            ],
                          ),
                        ),
                        if (draft.questions.length > 1)
                          IconButton(
                            icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                            onPressed: () => onRemoveQuestion(index),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: ElevatedButton.icon(
              onPressed: onAddQuestion,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Question'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.accentColor,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Center Stage Active Question Editor
class _QuestionStageEditor extends StatelessWidget {
  final int index;
  final int totalQuestions;
  final DraftQuestion question;
  final bool isQuiz;
  final QuizBuilderCubit cubit;

  const _QuestionStageEditor({
    required this.index,
    required this.totalQuestions,
    required this.question,
    required this.isQuiz,
    required this.cubit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Question ${index + 1} of $totalQuestions',
                style: AppTypography.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: context.accentColor,
                ),
              ),
              if (totalQuestions > 1)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  tooltip: 'Delete Question',
                  onPressed: () => cubit.removeQuestion(index),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('q_text_input_$index'),
            initialValue: question.text,
            onChanged: (val) => cubit.updateQuestionText(index, val),
            maxLines: 3,
            minLines: 2,
            style: AppTypography.inter(fontSize: 16, color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Type your question here...',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isQuiz ? 'Answer Options (Select correct answer)' : 'Poll Options',
            style: AppTypography.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70),
          ),
          const SizedBox(height: 10),
          ...List.generate(
            question.options.length,
            (oIndex) => OptionEditorRow(
              index: oIndex,
              text: question.options[oIndex],
              isCorrect: question.correctIndices.contains(oIndex),
              isQuiz: isQuiz,
              onChanged: (val) => cubit.updateOptionText(index, oIndex, val),
              onRemove: () => cubit.removeOption(index, oIndex),
              onToggleCorrect: () => cubit.toggleCorrectOption(index, oIndex),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => cubit.addOption(index),
            icon: const Icon(Icons.add),
            label: const Text('Add Option'),
            style: TextButton.styleFrom(foregroundColor: context.accentColor),
          ),
        ],
      ),
    );
  }
}

/// Mobile Bottom Slide Deck Carousel Dock
class _MobileBottomSlideDock extends StatelessWidget {
  final DraftQuiz draft;
  final int activeQuestionIndex;
  final ValueChanged<int> onSelectQuestion;
  final VoidCallback onAddQuestion;
  final ValueChanged<int> onRemoveQuestion;
  final VoidCallback onOpenSettings;

  const _MobileBottomSlideDock({
    required this.draft,
    required this.activeQuestionIndex,
    required this.onSelectQuestion,
    required this.onAddQuestion,
    required this.onRemoveQuestion,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(draft.questions.length, (index) {
                    final isSelected = index == activeQuestionIndex;
                    return InkWell(
                      onTap: () => onSelectQuestion(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? context.accentColor : Colors.white12,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Q${index + 1}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.black : Colors.white70,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.add_circle, color: context.accentColor, size: 28),
              tooltip: 'Add Question',
              onPressed: onAddQuestion,
            ),
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.white70, size: 24),
              tooltip: 'Settings',
              onPressed: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }
}

/// Header title & description inputs for desktop right column
class _HeaderInputSection extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController infoController;
  final DraftQuiz draft;
  final QuizBuilderCubit cubit;

  const _HeaderInputSection({
    required this.titleController,
    required this.infoController,
    required this.draft,
    required this.cubit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quiz Information',
          style: AppTypography.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: titleController,
          style: const TextStyle(color: Colors.white),
          onChanged: (val) => cubit.updateSettings(val, infoController.text, draft.type),
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
          controller: infoController,
          style: const TextStyle(color: Colors.white),
          maxLines: 2,
          onChanged: (val) => cubit.updateSettings(titleController.text, val, draft.type),
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
    );
  }
}

/// Game settings section
class _GameSettingsSection extends StatelessWidget {
  final DraftQuiz draft;
  final QuizBuilderCubit cubit;

  const _GameSettingsSection({required this.draft, required this.cubit});

  static const _timeOptions = [10, 15, 20, 30, 45, 60];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Game Settings',
            style: AppTypography.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Time per question', style: AppTypography.inter(fontSize: 14, color: Colors.white)),
              DropdownButton<int>(
                value: draft.timePerQuestionSeconds,
                dropdownColor: AppColors.surface,
                underline: const SizedBox.shrink(),
                style: AppTypography.inter(fontSize: 14, color: Colors.white),
                items: _timeOptions
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text('${s}s'),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    cubit.updateGameConfig(timePerQuestionSeconds: val);
                  }
                },
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Scoring', style: AppTypography.inter(fontSize: 14, color: Colors.white)),
              SegmentedButton<QuizScoringMode>(
                segments: const [
                  ButtonSegment(value: QuizScoringMode.flat, label: Text('Flat')),
                  ButtonSegment(value: QuizScoringMode.speed, label: Text('Speed bonus')),
                ],
                selected: {draft.scoringMode},
                onSelectionChanged: (selection) {
                  cubit.updateGameConfig(scoringMode: selection.first);
                },
                style: SegmentedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white70,
                  selectedForegroundColor: Colors.black,
                  selectedBackgroundColor: context.accentColor,
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 24),
          _SettingSwitch(
            label: 'Shuffle answers',
            subtitle: 'Each player sees options in a different order',
            value: draft.shuffleAnswers,
            onChanged: (v) => cubit.updateGameConfig(shuffleAnswers: v),
          ),
          _SettingSwitch(
            label: 'Shuffle questions',
            subtitle: 'Randomize question order when the quiz starts',
            value: draft.shuffleQuestions,
            onChanged: (v) => cubit.updateGameConfig(shuffleQuestions: v),
          ),
          _SettingSwitch(
            label: 'Reveal answer',
            subtitle: 'Show correct option after timer',
            value: draft.revealAnswer,
            onChanged: (v) => cubit.updateGameConfig(revealAnswer: v),
          ),
        ],
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingSwitch({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.inter(fontSize: 14, color: Colors.white)),
                Text(subtitle, style: AppTypography.inter(fontSize: 11, color: Colors.white38)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: context.accentColor,
            activeThumbColor: Colors.black,
          ),
        ],
      ),
    );
  }
}
