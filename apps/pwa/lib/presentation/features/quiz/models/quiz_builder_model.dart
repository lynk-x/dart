class DraftQuiz {
  final String? id;
  final String forumId;
  final String title;
  final String info;
  final String type;
  final String status;
  final List<DraftQuestion> questions;

  const DraftQuiz({
    this.id,
    required this.forumId,
    required this.title,
    required this.info,
    this.type = 'quiz',
    this.status = 'draft',
    this.questions = const [],
  });

  DraftQuiz copyWith({
    String? id,
    String? forumId,
    String? title,
    String? info,
    String? type,
    String? status,
    List<DraftQuestion>? questions,
  }) {
    return DraftQuiz(
      id: id ?? this.id,
      forumId: forumId ?? this.forumId,
      title: title ?? this.title,
      info: info ?? this.info,
      type: type ?? this.type,
      status: status ?? this.status,
      questions: questions ?? this.questions,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'forum_id': forumId,
      'title': title,
      'info': info,
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
