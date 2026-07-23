import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../forum_skeletons.dart';
import 'poll_card.dart';
import 'poll_quiz_card_shell.dart';

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
    return SkeletonFade(child: _buildContent(context));
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      // Card shell + header render immediately — neither depends on the
      // fetch. Only the question/options region skeletons, sized to match
      // PollCard's real layout, so nothing resizes or recolors once loaded.
      return PollQuizCardShell(
        key: const ValueKey('skeleton'),
        isMe: widget.isMe,
        child: _PollSkeletonBody(isMe: widget.isMe),
      );
    }

    if (_questions.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('empty'));
    }

    return Column(
      key: const ValueKey('content'),
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

class _PollSkeletonBody extends StatelessWidget {
  final bool isMe;

  const _PollSkeletonBody({required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PollQuizCardHeader(isQuiz: false, isMe: isMe),
        const SizedBox(height: 10),
        // Question text — two lines, matching fontSize 15 line height.
        PollQuizSkeletonBar(isMe: isMe, height: 15, width: double.infinity, margin: const EdgeInsets.only(bottom: 6)),
        PollQuizSkeletonBar(isMe: isMe, height: 15, width: 140, margin: const EdgeInsets.only(bottom: 14)),
        // Two option rows, matching the real 42px-tall option buttons.
        PollQuizSkeletonBar(isMe: isMe, height: 42, margin: const EdgeInsets.only(bottom: 8)),
        PollQuizSkeletonBar(isMe: isMe, height: 42),
      ],
    );
  }
}
