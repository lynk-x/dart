import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'poll_card.dart';

/// Loads and renders a poll/quiz attached to a forum message.
///
/// Forum messages reference polls via `questionnaire_id`. This widget
/// fetches the questionnaire + its questions and renders a [PollCard] for
/// each question. Polls with `status != 'published'` are hidden.
class PollAttachment extends StatefulWidget {
  final String questionnaireId;

  const PollAttachment({super.key, required this.questionnaireId});

  @override
  State<PollAttachment> createState() => _PollAttachmentState();
}

class _PollAttachmentState extends State<PollAttachment> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _title;
  String _type = 'poll';
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
          .from('questionnaires')
          .select('title, type, status')
          .eq('id', widget.questionnaireId)
          .single();

      if (qData['status'] != 'published') {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Fetch questions
      final questions = await _supabase
          .from('questions')
          .select('id, question_text, options, order_index')
          .eq('questionnaire_id', widget.questionnaireId)
          .order('order_index', ascending: true);

      if (mounted) {
        setState(() {
          _title = qData['title'] as String?;
          _type = qData['type'] as String? ?? 'poll';
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
                color: Colors.white.withOpacity(0.6),
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
            isQuiz: _type == 'quiz',
          );
        }),
      ],
    );
  }
}
