import 'package:equatable/equatable.dart';
import '../models/quiz_builder_model.dart';

class QuizBuilderState extends Equatable {
  final DraftQuiz draft;
  final bool isSaving;
  final String? error;
  // Set once saveDraft() succeeds — the questionnaire now exists server-side
  // (as a draft, no forum_messages row yet) and can be published later.
  final String? questionnaireId;
  final bool isDraftSaved;
  // Set once publish() succeeds. The caller (PollCardEditor / QuizBuilderPage)
  // uses these to build a local optimistic ChatMessage, since
  // publish_questionnaire doesn't broadcast a realtime event the way
  // sendMessage() does.
  final bool isPublished;
  final String? publishedMessageId;
  final DateTime? publishedMessageCreatedAt;

  const QuizBuilderState({
    required this.draft,
    this.isSaving = false,
    this.error,
    this.questionnaireId,
    this.isDraftSaved = false,
    this.isPublished = false,
    this.publishedMessageId,
    this.publishedMessageCreatedAt,
  });

  QuizBuilderState copyWith({
    DraftQuiz? draft,
    bool? isSaving,
    String? error,
    String? questionnaireId,
    bool? isDraftSaved,
    bool? isPublished,
    String? publishedMessageId,
    DateTime? publishedMessageCreatedAt,
  }) {
    return QuizBuilderState(
      draft: draft ?? this.draft,
      isSaving: isSaving ?? this.isSaving,
      error: error,
      questionnaireId: questionnaireId ?? this.questionnaireId,
      isDraftSaved: isDraftSaved ?? this.isDraftSaved,
      isPublished: isPublished ?? this.isPublished,
      publishedMessageId: publishedMessageId ?? this.publishedMessageId,
      publishedMessageCreatedAt:
          publishedMessageCreatedAt ?? this.publishedMessageCreatedAt,
    );
  }

  @override
  List<Object?> get props => [
        draft,
        isSaving,
        error,
        questionnaireId,
        isDraftSaved,
        isPublished,
        publishedMessageId,
        publishedMessageCreatedAt,
      ];
}
