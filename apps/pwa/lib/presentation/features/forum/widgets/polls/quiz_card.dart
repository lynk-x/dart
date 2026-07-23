import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../cubit/forum_cubit.dart';
import '../forum_skeletons.dart';
import 'poll_quiz_card_shell.dart';

/// Quiz body: loads and renders a quiz's join-launcher card attached to a
/// forum message.
///
/// A quiz IS its announcing forum_messages row — see surveys.quiz_sessions,
/// keyed on message_id. A quiz is a session to join rather than a question
/// to answer inline, so this renders a single join card, not a PollCard.
/// Hidden while `status != 'published'`.
class QuizBody extends StatefulWidget {
  final String messageId;
  final bool isMe;

  const QuizBody({super.key, required this.messageId, this.isMe = true});

  @override
  State<QuizBody> createState() => _QuizBodyState();
}

class _QuizBodyState extends State<QuizBody> {
  SupabaseClient get _supabase => Supabase.instance.client;
  bool _isLoading = true;
  bool _isPublished = false;
  String _title = '';
  String _quizState = 'lobby';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sessionData = await _supabase
          .schema('api')
          .from('v1_quiz_sessions')
          .select('title, status, quiz_state')
          .eq('message_id', widget.messageId)
          .single();

      if (mounted) {
        setState(() {
          _title = sessionData['title'] as String? ?? '';
          _isPublished = sessionData['status'] == 'published';
          _quizState = sessionData['quiz_state'] as String? ?? 'lobby';
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SkeletonFade(child: _buildContent(context));
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      // Card shell + header render immediately — neither depends on the
      // fetch. Only the title/join-button region skeletons, sized to match
      // _QuizJoinCard's real layout, so nothing resizes or recolors once
      // loaded.
      return PollQuizCardShell(
        key: const ValueKey('skeleton'),
        isMe: widget.isMe,
        child: _QuizSkeletonBody(isMe: widget.isMe),
      );
    }

    if (!_isPublished) {
      return const SizedBox.shrink(key: ValueKey('empty'));
    }

    return _QuizJoinCard(
      key: const ValueKey('content'),
      messageId: widget.messageId,
      title: _title,
      quizState: _quizState,
      isMe: widget.isMe,
    );
  }
}

class _QuizSkeletonBody extends StatelessWidget {
  final bool isMe;

  const _QuizSkeletonBody({required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PollQuizCardHeader(isQuiz: true, isMe: isMe),
        const SizedBox(height: 10),
        // Title — one line, matching fontSize 15 line height. Width varies
        // per quiz, so this stays shorter than the poll's two-line question.
        PollQuizSkeletonBar(isMe: isMe, height: 15, width: 160, margin: const EdgeInsets.only(bottom: 14)),
        // Join button, matching the real 44px-tall (12 vertical padding +
        // text) button.
        PollQuizSkeletonBar(isMe: isMe, height: 44),
      ],
    );
  }
}

class _QuizJoinCard extends StatelessWidget {
  final String messageId;
  final String title;
  final String quizState;
  final bool isMe;

  const _QuizJoinCard({
    super.key,
    required this.messageId,
    required this.title,
    required this.quizState,
    required this.isMe,
  });

  bool get _isLive => quizState == 'playing' || quizState == 'reveal' || quizState == 'leaderboard';
  bool get _isEnded => quizState == 'finished';

  String get _buttonLabel {
    if (_isEnded) return 'Quiz Ended';
    if (quizState == 'podium') return 'View Results';
    if (_isLive) return 'Rejoin — Live';
    return 'Join Quiz';
  }

  @override
  Widget build(BuildContext context) {
    bool isOrganizer = false;
    String? forumReference;
    try {
      final forumCubit = context.read<ForumCubit>();
      isOrganizer = forumCubit.state.isOrganizer;
      forumReference = forumCubit.forumReference;
    } catch (_) {}

    final onCardColor = PollQuizCardShell.onCardColor(isMe);

    return PollQuizCardShell(
      isMe: isMe,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PollQuizCardHeader(
            isQuiz: true,
            isMe: isMe,
            trailing: _isLive
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 4),
                      const Text('LIVE', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w700)),
                    ],
                  )
                : null,
          ),
          const SizedBox(height: 10),
          if (title.isNotEmpty)
            Text(
              title,
              style: TextStyle(color: onCardColor, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isEnded || forumReference == null
                  ? null
                  : () => context.push(
                        '/forum/$forumReference/quiz/$messageId',
                        extra: {'isHost': isOrganizer},
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                disabledBackgroundColor: onCardColor.withValues(alpha: 0.18),
                disabledForegroundColor: onCardColor.withValues(alpha: 0.4),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(_buttonLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
