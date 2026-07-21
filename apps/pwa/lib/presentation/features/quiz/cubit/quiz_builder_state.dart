import 'package:equatable/equatable.dart';
import '../models/quiz_builder_model.dart';

class QuizBuilderState extends Equatable {
  final DraftQuiz draft;
  final bool isSaving;
  final String? error;
  final bool isSuccess;
  // Set once publish() succeeds — the caller (PollCardEditor / QuizBuilderPage)
  // uses these to build a local optimistic ChatMessage, since create_poll /
  // create_quiz don't broadcast a realtime event the way sendMessage() does.
  final String? createdMessageId;
  final DateTime? createdMessageCreatedAt;

  const QuizBuilderState({
    required this.draft,
    this.isSaving = false,
    this.error,
    this.isSuccess = false,
    this.createdMessageId,
    this.createdMessageCreatedAt,
  });

  QuizBuilderState copyWith({
    DraftQuiz? draft,
    bool? isSaving,
    String? error,
    bool? isSuccess,
    String? createdMessageId,
    DateTime? createdMessageCreatedAt,
  }) {
    return QuizBuilderState(
      draft: draft ?? this.draft,
      isSaving: isSaving ?? this.isSaving,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
      createdMessageId: createdMessageId ?? this.createdMessageId,
      createdMessageCreatedAt:
          createdMessageCreatedAt ?? this.createdMessageCreatedAt,
    );
  }

  @override
  List<Object?> get props => [
        draft,
        isSaving,
        error,
        isSuccess,
        createdMessageId,
        createdMessageCreatedAt,
      ];
}
