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
  final List<int> optionOrder;

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
    this.optionOrder = const [],
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
    List<int>? optionOrder,
    bool clearMyAnswer = false,
  }) {
    return QuizState(
      status: status ?? this.status,
      questionnaire: questionnaire ?? this.questionnaire,
      currentQuestion: currentQuestion ?? this.currentQuestion,
      leaderboard: leaderboard ?? this.leaderboard,
      timeLeft: timeLeft ?? this.timeLeft,
      myAnswerIndex:
          clearMyAnswer ? null : (myAnswerIndex ?? this.myAnswerIndex),
      errorMessage: errorMessage ?? this.errorMessage,
      isHost: isHost ?? this.isHost,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      optionOrder: optionOrder ?? this.optionOrder,
    );
  }

  /// Options for the current question in **display** order — the raw
  /// stored list when unshuffled, or reordered per optionOrder otherwise.
  List<dynamic> get displayOptions {
    final raw = currentQuestion?['options'];
    if (raw is! List) return const [];
    if (optionOrder.isEmpty) return raw;
    return optionOrder.map((storedIndex) => raw[storedIndex]).toList();
  }

  /// Correct option indices for the current question, in **display**
  /// order/space — null until api.v1_questions starts returning them
  /// (quiz_state past 'playing'). See QuizRepository's doc comment for why
  /// this is gated server-side.
  List<int>? get correctOptionIndices {
    final raw = currentQuestion?['correct_options'];
    if (raw is! List) return null;
    final storedIndices = raw.map((e) => (e as num).toInt()).toSet();
    if (optionOrder.isEmpty) return storedIndices.toList();
    // Map each stored-correct-index to its display position.
    final displayIndices = <int>[];
    for (var displayPos = 0; displayPos < optionOrder.length; displayPos++) {
      if (storedIndices.contains(optionOrder[displayPos])) {
        displayIndices.add(displayPos);
      }
    }
    return displayIndices;
  }

  /// My submitted answer, translated from stored index to display index so
  /// ChallengeScreen (which only knows about display positions) highlights
  /// the button the user actually tapped.
  int? get myAnswerDisplayIndex {
    if (myAnswerIndex == null) return null;
    if (optionOrder.isEmpty) return myAnswerIndex;
    final displayPos = optionOrder.indexOf(myAnswerIndex!);
    return displayPos == -1 ? null : displayPos;
  }

  /// Translates a tapped display position back to the stored index that
  /// must be sent to submitAnswer (scoring/correct-answer checks are all
  /// keyed to stored order server-side).
  int storedIndexForDisplay(int displayIndex) {
    if (optionOrder.isEmpty) return displayIndex;
    return optionOrder[displayIndex];
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
        optionOrder,
      ];
}
