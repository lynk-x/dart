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
  bool _topSectionExpanded = true;

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
          AppSnackBars.showSuccess(context, 'Quiz published successfully!');
          context.pop();
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
                  onPressed: () => cubit.publish(widget.messageType),
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
                    InkWell(
                      onTap: () => setState(
                          () => _topSectionExpanded = !_topSectionExpanded),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              isQuiz ? 'Create a LiveQuiz' : 'Create Poll',
                              style: AppTypography.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white),
                            ),
                          ),
                          Icon(
                            _topSectionExpanded
                                ? Icons.unfold_less
                                : Icons.unfold_more,
                            color: Colors.white54,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      alignment: Alignment.topCenter,
                      child: !_topSectionExpanded
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _titleController,
                                  style: const TextStyle(color: Colors.white),
                                  onChanged: (val) => cubit.updateSettings(
                                      val, _infoController.text, draft.type),
                                  decoration: InputDecoration(
                                    labelText: 'Title',
                                    labelStyle:
                                        const TextStyle(color: Colors.white54),
                                    filled: true,
                                    fillColor:
                                        Colors.white.withValues(alpha: 0.05),
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
                                    labelStyle:
                                        const TextStyle(color: Colors.white54),
                                    filled: true,
                                    fillColor:
                                        Colors.white.withValues(alpha: 0.05),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                if (isQuiz) ...[
                                  const SizedBox(height: 16),
                                  _GameSettingsSection(
                                      draft: draft, cubit: cubit),
                                ],
                              ],
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
        title: const Text('Discard quiz?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'You have unsaved progress on this quiz. It will be lost if you leave now.',
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
        ],
      ),
    );
  }
}

/// Game configuration controls — time per question, scoring mode, shuffle,
/// and reveal-answer toggle. Quiz-only (polls have no timer/scoring/reveal
/// concept), so this is never shown when draft.type == 'poll'.
class _GameSettingsSection extends StatelessWidget {
  final DraftQuiz draft;
  final QuizBuilderCubit cubit;

  const _GameSettingsSection({required this.draft, required this.cubit});

  static const _timeOptions = [10, 15, 20, 30, 45, 60];

  static const Map<QuizScoringMode, String> _scoringDescriptions = {
    QuizScoringMode.flat:
        'Every correct answer earns the same points, no matter how fast it was answered.',
    QuizScoringMode.speed:
        'Correct answers earn up to +50% more points the faster they\'re submitted.',
  };

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
          Text('Game settings',
              style: AppTypography.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70)),
          const SizedBox(height: 12),

          // Time per question
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Time per question',
                  style:
                      AppTypography.inter(fontSize: 14, color: Colors.white)),
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

          // Scoring mode
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Scoring',
                  style:
                      AppTypography.inter(fontSize: 14, color: Colors.white)),
              SegmentedButton<QuizScoringMode>(
                segments: const [
                  ButtonSegment(
                    value: QuizScoringMode.flat,
                    label: Text('Standard'),
                  ),
                  ButtonSegment(
                    value: QuizScoringMode.speed,
                    label: Text('Speed bonus'),
                  ),
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
          const SizedBox(height: 6),
          Text(
            _scoringDescriptions[draft.scoringMode] ?? '',
            style: AppTypography.inter(fontSize: 11, color: Colors.white38),
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
          _SettingCheckbox(
            label: 'Reveal correct answer',
            subtitle: 'Show right/wrong styling before moving to standings',
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
                Text(label,
                    style:
                        AppTypography.inter(fontSize: 14, color: Colors.white)),
                Text(subtitle,
                    style: AppTypography.inter(
                        fontSize: 11, color: Colors.white38)),
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

class _SettingCheckbox extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingCheckbox({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTypography.inter(
                          fontSize: 14, color: Colors.white)),
                  Text(subtitle,
                      style: AppTypography.inter(
                          fontSize: 11, color: Colors.white38)),
                ],
              ),
            ),
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: context.accentColor,
              checkColor: Colors.black,
              side: const BorderSide(color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}
