import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/shared/screens/system_error_screen.dart';

import '../cubit/quiz_cubit.dart';
import '../cubit/quiz_state.dart';
import 'lobby_screen.dart';
import 'challenge_screen.dart';
import 'leaderboard_screen.dart';
import 'podium_screen.dart';

/// Watches [QuizCubit]'s status and renders the matching presentational
/// screen. All real state-machine logic lives in the Cubit — this widget is
/// deliberately thin, just a switch.
class QuizOrchestratorScreen extends StatelessWidget {
  const QuizOrchestratorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QuizCubit, QuizState>(
      builder: (context, state) {
        final cubit = context.read<QuizCubit>();

        switch (state.status) {
          case QuizStatus.initial:
            return const Scaffold(
              backgroundColor: AppColors.primaryBackground,
              body: Center(child: CircularProgressIndicator()),
            );

          case QuizStatus.lobby:
            return LobbyScreen(
              questionnaire: state.questionnaire ?? const {},
              isHost: state.isHost,
              onStart: state.isHost ? cubit.startQuiz : null,
            );

          case QuizStatus.playing:
          case QuizStatus.reveal:
            // options is swapped for the (possibly per-user-shuffled)
            // display order; ChallengeScreen only ever deals in display
            // positions — index translation to/from stored order happens
            // in QuizState/QuizCubit, not here or in ChallengeScreen.
            final displayQuestion = {
              ...?state.currentQuestion,
              'options': state.displayOptions,
            };
            return ChallengeScreen(
              question: displayQuestion,
              timeLeft: state.timeLeft,
              selectedIndex: state.myAnswerDisplayIndex,
              onOptionSelected: cubit.submitAnswer,
              isHost: state.isHost,
              // Pausing has no server-side counterpart today (no 'paused'
              // quiz_state) — until that exists, the button has nothing to
              // wire to.
              onPause: null,
              onNext: state.isHost && state.status == QuizStatus.reveal
                  ? cubit.showLeaderboard
                  : null,
              onBack: () => context.pop(),
              // null (not just empty) when info.reveal_answer is false, so
              // ChallengeScreen's existing "no reveal styling" path applies
              // even past 'playing' — see its own doc comment.
              correctOptionIndices: _revealAnswerEnabled(state)
                  ? state.correctOptionIndices
                  : null,
            );

          case QuizStatus.leaderboard:
            final questionsCount =
                state.questionnaire?['questions_count'] as int? ?? 0;
            final annotated =
                _withCurrentUserFlag(state.leaderboard, cubit.userId);
            final myEntry = _findCurrentUser(annotated);
            return LeaderboardScreen(
              leaderboard: annotated,
              userScore: (myEntry?['total_score'] as num?)?.toInt() ?? 0,
              userRank: _rankOf(annotated, cubit.userId),
              isHost: state.isHost,
              onNext: state.isHost ? cubit.nextQuestion : null,
              isLastQuestion: state.currentQuestionIndex + 1 >= questionsCount,
            );

          case QuizStatus.podium:
            final annotated =
                _withCurrentUserFlag(state.leaderboard, cubit.userId);
            final myEntry = _findCurrentUser(annotated);
            return PodiumScreen(
              winners: annotated,
              finalScore: (myEntry?['total_score'] as num?)?.toInt() ?? 0,
              onExit: () {
                if (state.isHost) cubit.closeQuiz();
                context.pop();
              },
              isHost: state.isHost,
            );

          case QuizStatus.finished:
            return Scaffold(
              backgroundColor: AppColors.primaryBackground,
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Quiz ended',
                      style: AppTypography.h2.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('Back to forum'),
                    ),
                  ],
                ),
              ),
            );

          case QuizStatus.error:
            return SystemErrorScreen(
              title: 'Quiz Error',
              message: state.errorMessage ??
                  'Something went wrong loading this quiz.',
              buttonText: 'Back to forum',
              onAction: () => context.pop(),
            );
        }
      },
    );
  }

  /// Whether the reveal step should show correct/wrong styling at all —
  /// configurable via the builder's "Reveal correct answer" toggle, default
  /// true (today's only behavior) so unset/legacy quizzes are unchanged.
  bool _revealAnswerEnabled(QuizState state) {
    return state.questionnaire?['reveal_answer'] as bool? ?? true;
  }

  /// The leaderboard RPC (`get_quiz_leaderboard`) does not return an
  /// `is_current_user` column, so LeaderboardScreen's own check for it is
  /// always false unless annotated here first.
  List<Map<String, dynamic>> _withCurrentUserFlag(
    List<Map<String, dynamic>> leaderboard,
    String userId,
  ) {
    return leaderboard
        .map((entry) => {
              ...entry,
              'is_current_user': entry['user_id'] == userId,
            })
        .toList();
  }

  Map<String, dynamic>? _findCurrentUser(
      List<Map<String, dynamic>> leaderboard) {
    for (final entry in leaderboard) {
      if (entry['is_current_user'] == true) return entry;
    }
    return null;
  }

  int? _rankOf(List<Map<String, dynamic>> leaderboard, String userId) {
    final index = leaderboard.indexWhere((e) => e['user_id'] == userId);
    return index == -1 ? null : index + 1;
  }
}
