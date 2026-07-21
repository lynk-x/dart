import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'poll_card.dart';

/// Poll body: loads and renders a poll attached to a forum message.
///
/// A poll IS its announcing forum_messages row — see surveys.polls, keyed on
/// message_id. Renders a [PollCard] per question (a poll is always exactly
/// one question in practice, but this stays list-shaped to match the
/// underlying table). Hidden while `status != 'published'`.
class PollBody extends StatefulWidget {
  final String messageId;
  final bool isMe;

  const PollBody({super.key, required this.messageId, this.isMe = true});

  @override
  State<PollBody> createState() => _PollBodyState();
}

class _PollBodyState extends State<PollBody> {
  SupabaseClient get _supabase => Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _questions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
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
      return const _PollLoadingIndicator();
    }

    if (_questions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _questions.map((q) {
        final options =
            (q['options'] as List?)?.map((o) => o.toString()).toList() ?? [];
        return PollCard(
          messageId: widget.messageId,
          questionId: q['id'] as String,
          questionText: q['question_text'] as String,
          options: options,
          isQuiz: false,
          isMe: widget.isMe,
        );
      }).toList(),
    );
  }
}

class _PollLoadingIndicator extends StatelessWidget {
  const _PollLoadingIndicator();

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
