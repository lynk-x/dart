/// Scoring behavior for a quiz. 'flat' gives 1 point per correct answer
/// (today's only behavior); 'speed' adds up to +50% for near-instant correct
/// answers, computed server-side in surveys.fn_calculate_response_score.
enum QuizScoringMode {
  flat,
  speed;

  String get value => name;

  static QuizScoringMode fromValue(String? value) {
    return QuizScoringMode.values.firstWhere(
      (m) => m.value == value,
      orElse: () => QuizScoringMode.flat,
    );
  }
}

class DraftQuiz {
  final String forumId;
  final String? channelId;
  final String? channelCreatedAt;
  final String title;
  final String info;
  final String type;
  final List<DraftQuestion> questions;

  // Game configs — all default to today's actual hardcoded runtime behavior,
  // so any quiz saved without ever touching these fields plays identically
  // to before they existed.
  final int timePerQuestionSeconds;
  final QuizScoringMode scoringMode;
  final bool shuffleAnswers;
  final bool shuffleQuestions;
  final bool revealAnswer;

  const DraftQuiz({
    required this.forumId,
    this.channelId,
    this.channelCreatedAt,
    required this.title,
    required this.info,
    this.type = 'quiz',
    this.questions = const [],
    this.timePerQuestionSeconds = 30,
    this.scoringMode = QuizScoringMode.flat,
    this.shuffleAnswers = false,
    this.shuffleQuestions = false,
    this.revealAnswer = true,
  });

  DraftQuiz copyWith({
    String? forumId,
    String? channelId,
    String? channelCreatedAt,
    String? title,
    String? info,
    String? type,
    List<DraftQuestion>? questions,
    int? timePerQuestionSeconds,
    QuizScoringMode? scoringMode,
    bool? shuffleAnswers,
    bool? shuffleQuestions,
    bool? revealAnswer,
  }) {
    return DraftQuiz(
      forumId: forumId ?? this.forumId,
      channelId: channelId ?? this.channelId,
      channelCreatedAt: channelCreatedAt ?? this.channelCreatedAt,
      title: title ?? this.title,
      info: info ?? this.info,
      type: type ?? this.type,
      questions: questions ?? this.questions,
      timePerQuestionSeconds:
          timePerQuestionSeconds ?? this.timePerQuestionSeconds,
      scoringMode: scoringMode ?? this.scoringMode,
      shuffleAnswers: shuffleAnswers ?? this.shuffleAnswers,
      shuffleQuestions: shuffleQuestions ?? this.shuffleQuestions,
      revealAnswer: revealAnswer ?? this.revealAnswer,
    );
  }

  /// Params for api.create_poll — a poll is always exactly one question, so
  /// `p_options` is that single question's option list.
  Map<String, dynamic> toCreatePollParams({required String messageType}) {
    return {
      'p_forum_id': forumId,
      'p_channel_id': channelId,
      'p_channel_created_at': channelCreatedAt,
      'p_content': title,
      'p_options': questions.isNotEmpty ? questions.first.options : <String>[],
      'p_message_type': messageType,
    };
  }

  /// Params for api.create_quiz.
  Map<String, dynamic> toCreateQuizParams({required String messageType}) {
    return {
      'p_forum_id': forumId,
      'p_channel_id': channelId,
      'p_channel_created_at': channelCreatedAt,
      'p_content': title,
      'p_message_type': messageType,
      'p_questions': questions.map((q) => q.toMap()).toList(),
      'p_time_per_question_seconds': timePerQuestionSeconds,
      'p_scoring_mode': scoringMode.value,
      'p_shuffle_answers': shuffleAnswers,
      'p_shuffle_questions': shuffleQuestions,
      'p_reveal_answer': revealAnswer,
    };
  }
}

class DraftQuestion {
  final String? id;
  final String text;
  final List<String> options;
  final List<int> correctIndices;

  const DraftQuestion({
    this.id,
    this.text = '',
    this.options = const ['', '', '', ''],
    this.correctIndices = const [],
  });

  DraftQuestion copyWith({
    String? id,
    String? text,
    List<String>? options,
    List<int>? correctIndices,
  }) {
    return DraftQuestion(
      id: id ?? this.id,
      text: text ?? this.text,
      options: options ?? this.options,
      correctIndices: correctIndices ?? this.correctIndices,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'question_text': text,
      'options': options,
      'correct': {for (var i in correctIndices) i.toString(): true},
    };
  }
}
