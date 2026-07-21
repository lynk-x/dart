import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'poll_card.dart';
import '../../cubit/forum_cubit.dart';
import '../../models/forum_model.dart';

/// Loads and renders a poll/quiz attached to a forum message.
///
/// A poll/quiz IS its announcing forum_messages row — see surveys.polls /
/// surveys.quiz_sessions, both keyed on message_id. This widget fetches the
/// poll/quiz config (from whichever table messageType indicates) + its
/// questions. Polls render a [PollCard] per question inline; quizzes are a
/// session to join rather than a question to answer inline, so they render a
/// single join-launcher card instead. A poll/quiz with `status != 'published'`
/// is hidden.
class PollAttachment extends StatefulWidget {
  final String messageId;
  final MessageType messageType;

  const PollAttachment({
    super.key,
    required this.messageId,
    required this.messageType,
  });

  @override
  State<PollAttachment> createState() => _PollAttachmentState();
}

class _PollAttachmentState extends State<PollAttachment> {
  SupabaseClient get _supabase => Supabase.instance.client;
  bool _isLoading = true;
  String _quizState = 'lobby';
  int _questionsCount = 0;
  List<Map<String, dynamic>> _questions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.messageType.isQuiz) {
        final sessionData = await _supabase
            .schema('api')
            .from('v1_quiz_sessions')
            .select('status, quiz_state, questions_count')
            .eq('message_id', widget.messageId)
            .single();

        if (sessionData['status'] != 'published') {
          if (mounted) setState(() => _isLoading = false);
          return;
        }

        if (mounted) {
          setState(() {
            _quizState = sessionData['quiz_state'] as String? ?? 'lobby';
            _questionsCount = sessionData['questions_count'] as int? ?? 0;
            _isLoading = false;
          });
        }
        return;
      }

      final pollData = await _supabase
          .schema('api')
          .from('v1_polls')
          .select('status')
          .eq('message_id', widget.messageId)
          .single();

      if (pollData['status'] != 'published') {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final questions = await _supabase
          .schema('api')
          .from('v1_questions')
          .select('id, question_text, options, order_index')
          .eq('message_id', widget.messageId)
          .order('order_index', ascending: true);

      if (mounted) {
        setState(() {
          _questions = List<Map<String, dynamic>>.from(questions);
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

    if (widget.messageType.isQuiz) {
      return _QuizJoinCard(
        messageId: widget.messageId,
        questionsCount: _questionsCount,
        quizState: _quizState,
      );
    }

    if (_questions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _questions.map((q) {
        final options = (q['options'] as List?)
                ?.map((o) => o.toString())
                .toList() ??
            [];
        return PollCard(
          messageId: widget.messageId,
          questionId: q['id'] as String,
          questionText: q['question_text'] as String,
          options: options,
          isQuiz: false,
        );
      }).toList(),
    );
  }
}

class _QuizJoinCard extends StatelessWidget {
  final String messageId;
  final int questionsCount;
  final String quizState;

  const _QuizJoinCard({
    required this.messageId,
    required this.questionsCount,
    required this.quizState,
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

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.quiz_outlined, color: Color(0xFF00FF00), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Quiz',
                style: TextStyle(color: Color(0xFF00FF00), fontSize: 12, fontWeight: FontWeight.w600),
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
          if (questionsCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '$questionsCount question${questionsCount == 1 ? '' : 's'}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
            ),
          ],
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
                backgroundColor: const Color(0xFF20F928),
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.4),
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
