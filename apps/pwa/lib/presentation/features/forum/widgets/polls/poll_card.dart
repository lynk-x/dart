import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Displays a single poll question with live-updating results.
///
/// Polls are attached to forum messages via `questionnaire_id`. When the user
/// taps an option, the response is inserted into the `responses` table and
/// the UI shows the aggregated results from `vw_poll_results`.
class PollCard extends StatefulWidget {
  final String questionnaireId;
  final String questionId;
  final String questionText;
  final List<String> options;
  final bool isQuiz;

  const PollCard({
    super.key,
    required this.questionnaireId,
    required this.questionId,
    required this.questionText,
    required this.options,
    this.isQuiz = false,
  });

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  final _supabase = Supabase.instance.client;
  int? _selectedIndex;
  bool _hasVoted = false;
  bool _isSubmitting = false;
  Map<int, int> _results = {}; // optionIndex -> count
  int _totalVotes = 0;

  @override
  void initState() {
    super.initState();
    _checkExistingVote();
    _fetchResults();
  }

  Future<void> _checkExistingVote() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final existing = await _supabase
        .from('responses')
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
        .from('vw_poll_results')
        .select('selected_option_index, response_count')
        .eq('question_id', widget.questionId);

    if (!mounted) return;

    final results = <int, int>{};
    int total = 0;
    for (final row in data) {
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

    setState(() {
      _isSubmitting = true;
      _selectedIndex = index;
    });

    try {
      await _supabase.from('responses').insert({
        'questionnaire_id': widget.questionnaireId,
        'question_id': widget.questionId,
        'user_id': _supabase.auth.currentUser!.id,
        'selected_answer': [index],
      });

      setState(() {
        _hasVoted = true;
        _isSubmitting = false;
        _results[index] = (_results[index] ?? 0) + 1;
        _totalVotes++;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit vote: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          // Header
          Row(
            children: [
              Icon(
                widget.isQuiz ? Icons.quiz_outlined : Icons.poll_outlined,
                color: const Color(0xFF00FF00),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                widget.isQuiz ? 'Quiz' : 'Poll',
                style: TextStyle(
                  color: const Color(0xFF00FF00),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Question
          Text(
            widget.questionText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
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
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
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
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Text(
              option,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultBar(String option, double pct, int votes, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00FF00).withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            children: [
              // Background bar
              FractionallySizedBox(
                widthFactor: pct,
                child: Container(
                  height: 42,
                  color: isSelected
                      ? const Color(0xFF00FF00).withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
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
                            color: Color(0xFF00FF00), size: 16),
                      ),
                    Expanded(
                      child: Text(
                        option,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    Text(
                      '${(pct * 100).round()}%',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
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
