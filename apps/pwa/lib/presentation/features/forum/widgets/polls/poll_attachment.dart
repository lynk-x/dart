import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'poll_card.dart';
import '../../cubit/forum_cubit.dart';

/// Loads and renders a poll/quiz attached to a forum message.
///
/// Forum messages reference polls via `questionnaire_id`. This widget
/// fetches the questionnaire + its questions. Polls render a [PollCard] per
/// question inline; quizzes are a session to join rather than a question to
/// answer inline, so they render a single join-launcher card instead. Polls
/// with `status != 'published'` are hidden.
class PollAttachment extends StatefulWidget {
  final String questionnaireId;

  const PollAttachment({super.key, required this.questionnaireId});

  @override
  State<PollAttachment> createState() => _PollAttachmentState();
}

class _PollAttachmentState extends State<PollAttachment> {
  SupabaseClient get _supabase => Supabase.instance.client;
  bool _isLoading = true;
  String? _title;
  String _type = 'poll';
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
      // Fetch questionnaire metadata
      final qData = await _supabase
          .schema('api')
          .from('v1_questionnaires')
          .select('title, type, status, quiz_state, info')
          .eq('id', widget.questionnaireId)
          .single();

      if (qData['status'] != 'published') {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final type = qData['type'] as String? ?? 'poll';

      // Quizzes are a join-launcher card, not per-question inline voting —
      // no need to fetch every question up front.
      if (type == 'quiz') {
        final info = qData['info'] as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _title = qData['title'] as String?;
            _type = type;
            _quizState = qData['quiz_state'] as String? ?? 'lobby';
            _questionsCount = info?['questions_count'] as int? ?? 0;
            _isLoading = false;
          });
        }
        return;
      }

      // Fetch questions
      final questions = await _supabase
          .schema('api')
          .from('v1_questions')
          .select('id, question_text, options, order_index')
          .eq('questionnaire_id', widget.questionnaireId)
          .order('order_index', ascending: true);

      if (mounted) {
        setState(() {
          _title = qData['title'] as String?;
          _type = type;
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

    if (_type == 'quiz') {
      if (_title == null) return const SizedBox.shrink();
      return _QuizJoinCard(
        questionnaireId: widget.questionnaireId,
        title: _title!,
        questionsCount: _questionsCount,
        quizState: _quizState,
      );
    }

    if (_questions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_title != null && _title!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, top: 8),
            child: Text(
              _title!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ..._questions.map((q) {
          final options = (q['options'] as List?)
                  ?.map((o) => o.toString())
                  .toList() ??
              [];
          return PollCard(
            questionnaireId: widget.questionnaireId,
            questionId: q['id'] as String,
            questionText: q['question_text'] as String,
            options: options,
            isQuiz: false,
          );
        }),
      ],
    );
  }
}

class _QuizJoinCard extends StatelessWidget {
  final String questionnaireId;
  final String title;
  final int questionsCount;
  final String quizState;

  const _QuizJoinCard({
    required this.questionnaireId,
    required this.title,
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
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
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
                        '/forum/$forumReference/quiz/$questionnaireId',
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
