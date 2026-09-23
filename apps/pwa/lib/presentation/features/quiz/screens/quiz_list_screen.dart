import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

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
    if (result != null) {
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
    if (result == null || !mounted) return;
    // Hand the created-message result straight back up to forum_screen.dart,
    // same as if the organizer had used the plain "Create Quiz" path.
    context.pop(result);
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
    if (result == null || !mounted) return;
    context.pop(result);
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
            icon: const Icon(Icons.add, color: Colors.white),
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No LiveQuiz in this forum yet.\nCreate one and it\'ll show up here for next time.',
                  textAlign: TextAlign.center,
                  style: AppTypography.inter(color: Colors.white38, fontSize: 14),
                ),
              ),
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (live.isNotEmpty) ...[
                _SectionLabel('Live now'),
                const SizedBox(height: 10),
                for (final quiz in live) ...[
                  _PastQuizCard(
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
                _SectionLabel('Not started'),
                const SizedBox(height: 10),
                for (final quiz in notStarted) ...[
                  _PastQuizCard(
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
                _SectionLabel('Finished'),
                const SizedBox(height: 10),
                for (final quiz in finished) ...[
                  _PastQuizCard(
                    status: _QuizCardStatus.finished,
                    quiz: quiz,
                    onPrimary: () => _openQuiz(quiz),
                    onSecondary: () => _duplicate(quiz),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Text(
        text.toUpperCase(),
        style: AppTypography.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white38,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _PastQuizCard extends StatelessWidget {
  final Map<String, dynamic> quiz;
  final _QuizCardStatus status;
  final bool isDraft;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;
  // Only offered for live/not-started-and-published quizzes (null for
  // finished ones, which have nothing left to close, and for drafts, which
  // have no live session to force-close) — see QuizListScreen._forceClose's
  // doc comment for why this exists: today it's the only recovery path
  // for a quiz whose host disconnected before reaching Podium's Exit.
  final VoidCallback? onForceClose;

  const _PastQuizCard({
    required this.quiz,
    required this.status,
    this.isDraft = false,
    required this.onPrimary,
    required this.onSecondary,
    this.onForceClose,
  });

  static const _accent = Color(0xFFFF8A3D);

  @override
  Widget build(BuildContext context) {
    final title = quiz['title'] as String? ?? 'Untitled quiz';
    final questionsCount = quiz['questions_count'] as int? ?? 0;
    final createdAt = DateTime.tryParse(quiz['created_at'] as String? ?? '');
    final currentQuestionIndex = quiz['current_question_index'] as int?;
    final isLive = status == _QuizCardStatus.live;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLive
              ? context.accentColor.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.quiz_outlined,
                        color: _accent, size: 22),
                  ),
                  if (isLive)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.accentColor,
                          border: Border.all(color: AppColors.surface, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.interTight(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (isLive)
                      Text(
                        currentQuestionIndex != null && questionsCount > 0
                            ? '● Live · Question ${currentQuestionIndex + 1} of $questionsCount'
                            : '● Live',
                        style: AppTypography.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.accentColor,
                        ),
                      )
                    else
                      Text(
                        [
                          '$questionsCount question${questionsCount == 1 ? '' : 's'}',
                          if (createdAt != null) _formatDate(createdAt),
                        ].join(' · '),
                        style: AppTypography.inter(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    onPressed: onPrimary,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(_primaryIcon, size: 15),
                    label: Text(
                      _primaryLabel,
                      style: AppTypography.interTight(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 38,
                height: 38,
                child: OutlinedButton(
                  onPressed: onSecondary,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Icon(isDraft ? Icons.visibility_outlined : Icons.copy_rounded,
                      color: Colors.white70, size: 15),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 38,
                height: 38,
                child: onForceClose != null
                    ? PopupMenuButton<void>(
                        tooltip: 'More actions',
                        color: AppColors.surface,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        icon: const Icon(Icons.more_horiz,
                            color: Colors.white70, size: 18),
                        itemBuilder: (context) => [
                          PopupMenuItem<void>(
                            onTap: onForceClose,
                            child: const Text('Close quiz',
                                style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      )
                    : OutlinedButton(
                        // No further actions for a finished quiz today —
                        // deleting a quiz has no backend RPC yet.
                        onPressed: null,
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Icon(Icons.more_horiz,
                            color: Colors.white24, size: 18),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.month}/${local.day}/${local.year}';
  }

  IconData get _primaryIcon {
    switch (status) {
      case _QuizCardStatus.notStarted:
        return isDraft ? Icons.publish_outlined : Icons.play_circle_outline;
      case _QuizCardStatus.live:
        return Icons.play_arrow_rounded;
      case _QuizCardStatus.finished:
        return Icons.visibility_outlined;
    }
  }

  String get _primaryLabel {
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
