import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/core/utils/breakpoints.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';
import 'package:lynk_x/presentation/shared/widgets/list_action_card.dart';
import 'package:lynk_x/presentation/shared/widgets/section_label.dart';

enum _QuizCardStatus { notStarted, live, finished }

/// Lists quizzes previously posted (or drafted) in this forum, split into
/// three sections, in order: "Live now" (playing/reveal/leaderboard/
/// podium — actively running), "Not started" (either a genuine unpublished
/// draft — status='draft', no forum message yet — or a published-but-lobby
/// quiz that's already visible in the forum and just hasn't been started),
/// and "Finished" (closed, scores final). A draft and a lobby quiz share
/// the "Not started" section since both read as "nothing to resume/watch
/// yet" to an organizer scanning the list, but each card's actions differ:
/// a draft's primary action is Publish (post it to the forum) with Preview
/// as secondary (reopen the builder to review/edit first); a lobby quiz's
/// primary action is Start with Duplicate as secondary. Resume (live) and
/// View (finished) round out the primary actions for the other two
/// sections.
class QuizListScreen extends StatefulWidget {
  final String forumId;
  final String forumReference;
  final String? channelId;
  final String? channelCreatedAt;
  final String messageType;

  const QuizListScreen({
    super.key,
    required this.forumId,
    required this.forumReference,
    this.channelId,
    this.channelCreatedAt,
    required this.messageType,
  });

  @override
  State<QuizListScreen> createState() => _QuizListScreenState();
}

class _QuizListScreenState extends State<QuizListScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = quizRepository.getForumQuizList(widget.forumId);
  }

  // Only 'playing'/'reveal'/'leaderboard'/'podium' count as live — every
  // other value, including an unrecognized/null one, falls back to
  // "not started" rather than "live". This deliberately mirrors
  // QuizCubit._mapStatus's own default-to-lobby behavior (quiz_cubit.dart)
  // so a garbage/future quiz_state value can't make this list badge a
  // quiz "● Live" with a "Resume" button while opening it actually lands
  // on the Lobby screen — the two switches must agree on what an unknown
  // state means, or the list's promise and the orchestrator's render
  // diverge.
  _QuizCardStatus _statusOf(Map<String, dynamic> quiz) {
    // A draft has no live session at all yet — reads the same as "not
    // started" for section grouping, even though its quiz_state column is
    // just sitting at its unused default ('lobby').
    if (quiz['status'] == 'draft') return _QuizCardStatus.notStarted;

    switch (quiz['quiz_state'] as String?) {
      case 'finished':
        return _QuizCardStatus.finished;
      case 'playing':
      case 'reveal':
      case 'leaderboard':
      case 'podium':
        return _QuizCardStatus.live;
      default:
        return _QuizCardStatus.notStarted;
    }
  }

  /// Start (not started), Resume (live) and View (finished) are all the
  /// same navigation — QuizOrchestratorScreen/QuizCubit already render
  /// whichever screen matches the session's live quiz_state, lobby and
  /// finished included (see QuizOrchestratorScreen's QuizStatus.lobby and
  /// QuizStatus.finished cases). Never called for a draft (see _publish).
  void _openQuiz(Map<String, dynamic> quiz) {
    final questionnaireId = quiz['questionnaire_id'] as String;
    context.push('/forum/${widget.forumReference}/quiz/$questionnaireId',
        extra: {'isHost': true});
  }

  /// Publishes a draft directly from its list card — posts it to the forum
  /// (api.publish_questionnaire) without reopening the builder. Reuses
  /// QuizBuilderCubit purely as a thin one-shot RPC wrapper here (via a
  /// throwaway instance) since publish() already lives there.
  Future<void> _publish(Map<String, dynamic> quiz) async {
    final questionnaireId = quiz['questionnaire_id'] as String;
    try {
      await quizRepository.publishQuestionnaire(
        questionnaireId: questionnaireId,
        channelId: widget.channelId,
        channelCreatedAt: widget.channelCreatedAt,
        content: quiz['title'] as String? ?? 'Quiz',
        messageType: widget.messageType,
      );
      if (!mounted) return;
      AppSnackBars.showSuccess(context, 'Quiz published.');
      setState(() {
        _future = quizRepository.getForumQuizList(widget.forumId);
      });
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.showError(context, e.toFriendlyMessage());
    }
  }

  /// Reopens the builder pre-filled with this draft's content so the
  /// organizer can review or keep editing before publishing — the same
  /// "resume this draft" path as tapping it, just named for what it does
  /// from the card's secondary-action slot. See QuizBuilderPage's
  /// isResumingDraft check (keys off status='draft' + questionnaire_id).
  Future<void> _previewDraft(Map<String, dynamic> quiz) async {
    final result = await context.push<Map<String, dynamic>>(
      '/forum/${widget.forumReference}/quiz/create',
      extra: {
        'forumId': widget.forumId,
        'isOrganizer': true,
        'isLiveChat': widget.messageType == 'livechat_quiz',
        'channelId': widget.channelId,
        'channelCreatedAt': widget.channelCreatedAt,
        'duplicateFrom': quiz,
      },
    );
    if (!mounted) return;
    // Refresh either way: the draft may have been updated (or published)
    // while the builder was open.
    setState(() {
      _future = quizRepository.getForumQuizList(widget.forumId);
    });
    if (result != null && result.containsKey('messageId')) {
      // A publish happened from inside the builder — hand the created-
      // message result up to forum_screen.dart same as _duplicate does.
      context.pop(result);
    }
  }

  /// Force-closes a not-started or live quiz (quiz_state -> 'finished')
  /// without going through the live orchestrator/podium flow. This is the
  /// only recovery path today for a quiz whose host closed the app,
  /// disconnected, or navigated away before reaching Podium's own Exit
  /// button — api.update_quiz_state already lets any forum moderator/
  /// organizer transition any quiz state (not just its own host session),
  /// so a stuck quiz was already recoverable server-side; this just adds
  /// the UI to actually reach that path from outside a live session.
  Future<void> _forceClose(Map<String, dynamic> quiz) async {
    final questionnaireId = quiz['questionnaire_id'] as String;
    final title = quiz['title'] as String? ?? 'this quiz';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Close quiz?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This ends "$title" for everyone still in it. Scores already recorded stay final; nobody can rejoin.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Close quiz', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await quizRepository.updateQuizState(
        questionnaireId: questionnaireId,
        quizState: 'finished',
        questionIndex: (quiz['current_question_index'] as int?) ?? -1,
      );
      if (!mounted) return;
      setState(() {
        _future = quizRepository.getForumQuizList(widget.forumId);
      });
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.showError(context, e.toFriendlyMessage());
    }
  }

  Future<void> _duplicate(Map<String, dynamic> quiz) async {
    final result = await context.push<Map<String, dynamic>>(
      '/forum/${widget.forumReference}/quiz/create',
      extra: {
        'forumId': widget.forumId,
        'isOrganizer': true,
        'isLiveChat': widget.messageType == 'livechat_quiz',
        'channelId': widget.channelId,
        'channelCreatedAt': widget.channelCreatedAt,
        'duplicateFrom': quiz,
      },
    );
    if (!mounted) return;
    // Refresh either way: a draft-save still needs to show up in this list.
    setState(() {
      _future = quizRepository.getForumQuizList(widget.forumId);
    });
    // Only a publish result carries messageId — a draft-save result should
    // stay on this list rather than pop past it to the forum.
    if (result != null && result.containsKey('messageId')) {
      // Hand the created-message result straight back up to
      // forum_screen.dart, same as if the organizer had used the plain
      // "Create Quiz" path.
      context.pop(result);
    }
  }

  Future<void> _createNew() async {
    final result = await context.push<Map<String, dynamic>>(
      '/forum/${widget.forumReference}/quiz/create',
      extra: {
        'forumId': widget.forumId,
        'isOrganizer': true,
        'isLiveChat': widget.messageType == 'livechat_quiz',
        'channelId': widget.channelId,
        'channelCreatedAt': widget.channelCreatedAt,
      },
    );
    if (!mounted) return;
    // Refresh either way: a draft-save still needs to show up in this list.
    setState(() {
      _future = quizRepository.getForumQuizList(widget.forumId);
    });
    // Only a publish result carries messageId — a draft-save result should
    // stay on this list rather than pop past it to the forum.
    if (result != null && result.containsKey('messageId')) {
      context.pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          'LiveQuiz',
          style: AppTypography.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white, size: 32),
            tooltip: 'Create new quiz',
            onPressed: _createNew,
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white54),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load LiveQuizzes: ${snapshot.error!.toFriendlyMessage()}',
                textAlign: TextAlign.center,
                style: AppTypography.inter(color: Colors.white54, fontSize: 14),
              ),
            );
          }
          final quizzes = snapshot.data ?? const [];
          if (quizzes.isEmpty) {
            return EmptyState(
              message:
                  'No LiveQuiz in this forum yet.\nCreate one and it\'ll show up here for next time.',
              actionLabel: 'Create Quiz',
              onAction: _createNew,
            );
          }

          final notStarted = <Map<String, dynamic>>[];
          final live = <Map<String, dynamic>>[];
          final finished = <Map<String, dynamic>>[];
          for (final quiz in quizzes) {
            switch (_statusOf(quiz)) {
              case _QuizCardStatus.notStarted:
                notStarted.add(quiz);
              case _QuizCardStatus.live:
                live.add(quiz);
              case _QuizCardStatus.finished:
                finished.add(quiz);
            }
          }

          // Constrained to a max content width so cards don't stretch to
          // full bleed on wide desktop viewports — same pattern as
          // TicketScreen (Breakpoints.constrain).
          return Breakpoints.constrain(
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (live.isNotEmpty) ...[
                  const SectionLabel('Live now'),
                  const SizedBox(height: 10),
                  for (final quiz in live) ...[
                    _buildQuizCard(
                      status: _QuizCardStatus.live,
                      quiz: quiz,
                      onPrimary: () => _openQuiz(quiz),
                      onSecondary: () => _duplicate(quiz),
                      onForceClose: () => _forceClose(quiz),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 8),
                ],
                if (notStarted.isNotEmpty) ...[
                  const SectionLabel('Not started'),
                  const SizedBox(height: 10),
                  for (final quiz in notStarted) ...[
                    _buildQuizCard(
                      status: _QuizCardStatus.notStarted,
                      isDraft: quiz['status'] == 'draft',
                      quiz: quiz,
                      onPrimary: quiz['status'] == 'draft' ? () => _publish(quiz) : () => _openQuiz(quiz),
                      onSecondary: quiz['status'] == 'draft' ? () => _previewDraft(quiz) : () => _duplicate(quiz),
                      onForceClose: quiz['status'] == 'draft' ? null : () => _forceClose(quiz),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 8),
                ],
                if (finished.isNotEmpty) ...[
                  const SectionLabel('Finished'),
                  const SizedBox(height: 10),
                  for (final quiz in finished) ...[
                    _buildQuizCard(
                      status: _QuizCardStatus.finished,
                      quiz: quiz,
                      onPrimary: () => _openQuiz(quiz),
                      onSecondary: () => _duplicate(quiz),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
            maxWidth: Breakpoints.maxContentWidth,
          );
        },
      ),
    );
  }

  static const _quizAccent = Color(0xFFFF8A3D);

  /// Builds a quiz list-row as a [ListActionCard] — see that widget's own
  /// doc for the shared shape (leading icon/badge, title/subtitle, primary +
  /// up to two trailing action slots).
  Widget _buildQuizCard({
    required Map<String, dynamic> quiz,
    required _QuizCardStatus status,
    bool isDraft = false,
    required VoidCallback onPrimary,
    required VoidCallback onSecondary,
    // Only offered for live/not-started-and-published quizzes (null for
    // finished ones, which have nothing left to close, and for drafts,
    // which have no live session to force-close) — the only recovery path
    // today for a quiz whose host disconnected before reaching Podium's
    // Exit button.
    VoidCallback? onForceClose,
  }) {
    final title = quiz['title'] as String? ?? 'Untitled quiz';
    final questionsCount = quiz['questions_count'] as int? ?? 0;
    final createdAt = DateTime.tryParse(quiz['created_at'] as String? ?? '');
    final currentQuestionIndex = quiz['current_question_index'] as int?;
    final isLive = status == _QuizCardStatus.live;

    final subtitle = isLive
        ? (currentQuestionIndex != null && questionsCount > 0
            ? '● Live · Question ${currentQuestionIndex + 1} of $questionsCount'
            : '● Live')
        : [
            '$questionsCount question${questionsCount == 1 ? '' : 's'}',
            if (createdAt != null) _formatDate(createdAt),
          ].join(' · ');

    return Builder(
      builder: (context) => ListActionCard(
        leadingIcon: Icons.quiz_outlined,
        leadingIconColor: _quizAccent,
        showLeadingBadge: isLive,
        title: title,
        subtitle: subtitle,
        subtitleColor: isLive ? context.accentColor : null,
        highlighted: isLive,
        primaryIcon: _primaryIcon(status, isDraft),
        primaryLabel: _primaryLabel(status, isDraft),
        onPrimary: onPrimary,
        secondaryIcon: isDraft ? Icons.visibility_outlined : Icons.copy_rounded,
        onSecondary: onSecondary,
        overflowItems: onForceClose != null
            ? [
                PopupMenuItem<void>(
                  onTap: onForceClose,
                  child: const Text('Close quiz', style: TextStyle(color: Colors.redAccent)),
                ),
              ]
            : null,
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.month}/${local.day}/${local.year}';
  }

  IconData _primaryIcon(_QuizCardStatus status, bool isDraft) {
    switch (status) {
      case _QuizCardStatus.notStarted:
        return isDraft ? Icons.publish_outlined : Icons.play_circle_outline;
      case _QuizCardStatus.live:
        return Icons.play_arrow_rounded;
      case _QuizCardStatus.finished:
        return Icons.visibility_outlined;
    }
  }

  String _primaryLabel(_QuizCardStatus status, bool isDraft) {
    switch (status) {
      case _QuizCardStatus.notStarted:
        return isDraft ? 'Publish' : 'Start';
      case _QuizCardStatus.live:
        return 'Resume';
      case _QuizCardStatus.finished:
        return 'View';
    }
  }
}
