/// Scoring behavior for a quiz. 'flat' gives 1 point per correct answer
/// (today's only behavior); 'speed' adds up to +50% for near-instant correct
/// answers, computed server-side in internal.fn_calculate_response_score.
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
  final String? id;
  final String forumId;
  final String title;
  final String info;
  final String type;
  final String status;
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
    this.id,
    required this.forumId,
    required this.title,
    required this.info,
    this.type = 'quiz',
    this.status = 'draft',
    this.questions = const [],
    this.timePerQuestionSeconds = 30,
    this.scoringMode = QuizScoringMode.flat,
    this.shuffleAnswers = false,
    this.shuffleQuestions = false,
    this.revealAnswer = true,
  });

  DraftQuiz copyWith({
    String? id,
    String? forumId,
    String? title,
    String? info,
    String? type,
    String? status,
    List<DraftQuestion>? questions,
    int? timePerQuestionSeconds,
    QuizScoringMode? scoringMode,
    bool? shuffleAnswers,
    bool? shuffleQuestions,
    bool? revealAnswer,
  }) {
    return DraftQuiz(
      id: id ?? this.id,
      forumId: forumId ?? this.forumId,
      title: title ?? this.title,
      info: info ?? this.info,
      type: type ?? this.type,
      status: status ?? this.status,
      questions: questions ?? this.questions,
      timePerQuestionSeconds:
          timePerQuestionSeconds ?? this.timePerQuestionSeconds,
      scoringMode: scoringMode ?? this.scoringMode,
      shuffleAnswers: shuffleAnswers ?? this.shuffleAnswers,
      shuffleQuestions: shuffleQuestions ?? this.shuffleQuestions,
      revealAnswer: revealAnswer ?? this.revealAnswer,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'forum_id': forumId,
      'title': title,
      // info is a jsonb object server-side — nesting the description plus
      // game configs here (rather than sending a bare string) is what the
      // runtime (QuizCubit, QuizOrchestratorScreen) actually expects to read.
      'info': {
        'description': info,
        'questions_count': questions.length,
        'time_per_question_seconds': timePerQuestionSeconds,
        'scoring_mode': scoringMode.value,
        'shuffle_answers': shuffleAnswers,
        'shuffle_questions': shuffleQuestions,
        'reveal_answer': revealAnswer,
      },
      'type': type,
      'status': status,
      'questions': questions.map((q) => q.toMap()).toList(),
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
    this.options = const ['', ''],
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
      if (id != null) 'id': id,
      'question_text': text,
      'options': options,
      'correct': correctIndices,
    };
  }
}
