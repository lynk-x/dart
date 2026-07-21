import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../cubit/forum_cubit.dart';

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
    if (_isLoading) {
      return const _QuizLoadingIndicator();
    }

    if (!_isPublished) return const SizedBox.shrink();

    return _QuizJoinCard(
      messageId: widget.messageId,
      title: _title,
      quizState: _quizState,
      isMe: widget.isMe,
    );
  }
}

class _QuizLoadingIndicator extends StatelessWidget {
  const _QuizLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00FF00)),
        ),
      ),
    );
  }
}

class _QuizJoinCard extends StatelessWidget {
  final String messageId;
  final String title;
  final String quizState;
  final bool isMe;

  const _QuizJoinCard({
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

    // Same rule as PollCard: your own quiz reads in the accent color,
    // everyone else's in the neutral "their message" tone.
    final cardColor = isMe ? context.accentColor : AppColors.tertiary;
    final onCardColor = isMe ? Colors.black : Colors.white;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Same solid card style as PollCard — opaque, not translucent, since
        // this renders directly on the forum background with no bubble
        // wrapper behind it.
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.quiz_outlined, color: onCardColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Quiz',
                style: TextStyle(color: onCardColor, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              if (_isLive) ...[
                const SizedBox(width: 8),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                const Text('LIVE', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ],
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
