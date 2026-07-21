import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';


/// Displays a single poll question with live-updating results.
///
/// A poll IS its announcing forum_messages row (messageId is that message's
/// id — see surveys.polls). When the user taps an option, the response is
/// inserted into the `responses` table and the UI shows the aggregated
/// results from `vw_poll_results`.
class PollCard extends StatefulWidget {
  final String messageId;
  final String questionId;
  final String questionText;
  final List<String> options;
  final bool isQuiz;

  const PollCard({
    super.key,
    required this.messageId,
    required this.questionId,
    required this.questionText,
    required this.options,
    this.isQuiz = false,
  });

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  SupabaseClient get _supabase => Supabase.instance.client;
  int? _selectedIndex;
  bool _hasVoted = false;
  bool _isSubmitting = false;
  Map<int, int> _results = {}; // optionIndex -> count
  int _totalVotes = 0;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _checkExistingVote();
    _fetchResults();
    _channel = _supabase
        .channel('poll_results_${widget.questionId}')
        .onBroadcast(
          event: 'poll_results',
          callback: (payload) => _applyResults(payload['results'] as List?),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'surveys',
          table: 'poll_summaries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'question_id',
            value: widget.questionId,
          ),
          callback: (_) => _fetchResults(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _checkExistingVote() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final existing = await _supabase
        .schema('api').from('v1_responses')
        .select('selected_answer')
        .eq('question_id', widget.questionId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null && mounted) {
      final answer = existing['selected_answer'] as List?;
      setState(() {
        _hasVoted = true;
        if (answer != null && answer.isNotEmpty) {
          _selectedIndex = (answer[0] as num).toInt();
        }
      });
    }
  }

  Future<void> _fetchResults() async {
    final data = await _supabase
        .schema('api')
        .from('v1_poll_results')
        .select('selected_option_index, response_count')
        .eq('question_id', widget.questionId);

    if (!mounted) return;
    _applyResults(data);
  }

  /// Applies a list of {selected_option_index, response_count} rows, sourced
  /// either from a fresh fetch, a broadcast from another voter, or the
  /// submit_survey_response RPC's own return value.
  void _applyResults(List? rows) {
    if (!mounted || rows == null) return;

    final results = <int, int>{};
    int total = 0;
    for (final row in rows) {
      final idx = (row['selected_option_index'] as num).toInt();
      final count = (row['response_count'] as num).toInt();
      results[idx] = count;
      total += count;
    }

    setState(() {
      _results = results;
      _totalVotes = total;
    });
  }

  Future<void> _vote(int index) async {
    if (_hasVoted || _isSubmitting) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() {
      _isSubmitting = true;
      _selectedIndex = index;
    });

    try {
      // account_id resolution and per-question dedupe happen server-side.
      final response =
          await _supabase.schema('api').rpc('submit_survey_response', params: {
        'p_message_id': widget.messageId,
        'p_question_id': widget.questionId,
        'p_selected_answer': [index],
      });

      setState(() {
        _hasVoted = true;
        _isSubmitting = false;
      });
      final results = (response as Map?)?['results'] as List?;
      if (results != null) {
        _applyResults(results);
        _channel?.sendBroadcastMessage(
          event: 'poll_results',
          payload: {'results': results},
        );
      } else {
        _fetchResults();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppSnackBars.showError(context, 'Failed to submit vote: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF20F928),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                widget.isQuiz ? Icons.quiz_outlined : Icons.poll_outlined,
                color: Colors.black,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                widget.isQuiz ? 'Quiz' : 'Poll',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Question
          Text(
            widget.questionText,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),

          // Options
          ...widget.options.asMap().entries.map((entry) {
            final i = entry.key;
            final option = entry.value;
            final isSelected = _selectedIndex == i;
            final votes = _results[i] ?? 0;
            final pct = _totalVotes > 0 ? votes / _totalVotes : 0.0;

            if (_hasVoted) {
              return _buildResultBar(option, pct, votes, isSelected);
            }
            return _buildOptionButton(option, i);
          }),

          // Footer
          if (_totalVotes > 0 || _hasVoted)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '$_totalVotes vote${_totalVotes == 1 ? '' : 's'}',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOptionButton(String option, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isSubmitting ? null : () => _vote(index),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              option,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Selected option inverts to a solid black chip with a light proportional
  /// fill; unselected options stay on a grey base with a darker proportional
  /// fill — one fill rule (light base + darker fill = magnitude), selection
  /// itself signalled separately via the black border/fill and check badge.
  Widget _buildResultBar(String option, double pct, int votes, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: isSelected ? Border.all(color: Colors.black, width: 2) : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            children: [
              // Proportional fill
              FractionallySizedBox(
                widthFactor: pct,
                child: Container(
                  height: 42,
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: 0.16),
                ),
              ),
              // Content
              Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    if (isSelected)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.check_circle,
                            color: Color(0xFF20F928), size: 16),
                      ),
                    Expanded(
                      child: Text(
                        option,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : Colors.black.withValues(alpha: 0.55),
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.normal,
                        ),
                      ),
                    ),
                    Text(
                      '${(pct * 100).round()}%',
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : Colors.black.withValues(alpha: 0.55),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
