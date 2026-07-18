import 'package:equatable/equatable.dart';

enum QuizStatus {
  initial,
  lobby,
  playing,
  reveal,
  leaderboard,
  podium,
  finished,
  error
}

class QuizState extends Equatable {
  final QuizStatus status;
  final Map<String, dynamic>? questionnaire;
  final Map<String, dynamic>? currentQuestion;
  final List<Map<String, dynamic>> leaderboard;
  final int timeLeft;
  final int? myAnswerIndex;
  final String? errorMessage;
  final bool isHost;
  final int currentQuestionIndex;

  const QuizState({
    this.status = QuizStatus.initial,
    this.questionnaire,
    this.currentQuestion,
    this.leaderboard = const [],
    this.timeLeft = 0,
    this.myAnswerIndex,
    this.errorMessage,
    this.isHost = false,
    this.currentQuestionIndex = -1,
  });

  QuizState copyWith({
    QuizStatus? status,
    Map<String, dynamic>? questionnaire,
    Map<String, dynamic>? currentQuestion,
    List<Map<String, dynamic>>? leaderboard,
    int? timeLeft,
    int? myAnswerIndex,
    String? errorMessage,
    bool? isHost,
    int? currentQuestionIndex,
    bool clearMyAnswer = false,
  }) {
    return QuizState(
      status: status ?? this.status,
      questionnaire: questionnaire ?? this.questionnaire,
      currentQuestion: currentQuestion ?? this.currentQuestion,
      leaderboard: leaderboard ?? this.leaderboard,
      timeLeft: timeLeft ?? this.timeLeft,
      myAnswerIndex: clearMyAnswer ? null : (myAnswerIndex ?? this.myAnswerIndex),
      errorMessage: errorMessage ?? this.errorMessage,
      isHost: isHost ?? this.isHost,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
    );
  }

  /// Correct option indices for the current question — null until
  /// api.v1_questions starts returning them (quiz_state past 'playing').
  /// See QuizRepository's doc comment for why this is gated server-side.
  List<int>? get correctOptionIndices {
    final raw = currentQuestion?['correct_options'];
    if (raw is! List) return null;
    return raw.map((e) => (e as num).toInt()).toList();
  }

  @override
  List<Object?> get props => [
        status,
        questionnaire,
        currentQuestion,
        leaderboard,
        timeLeft,
        myAnswerIndex,
        errorMessage,
        isHost,
        currentQuestionIndex,
      ];
}
