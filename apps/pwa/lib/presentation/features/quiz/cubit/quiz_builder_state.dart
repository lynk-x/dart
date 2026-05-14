import 'package:equatable/equatable.dart';
import '../models/quiz_builder_model.dart';

class QuizBuilderState extends Equatable {
  final DraftQuiz draft;
  final bool isSaving;
  final String? error;
  final bool isSuccess;

  const QuizBuilderState({
    required this.draft,
    this.isSaving = false,
    this.error,
    this.isSuccess = false,
  });

  QuizBuilderState copyWith({
    DraftQuiz? draft,
    bool? isSaving,
    String? error,
    bool? isSuccess,
  }) {
    return QuizBuilderState(
      draft: draft ?? this.draft,
      isSaving: isSaving ?? this.isSaving,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }

  @override
  List<Object?> get props => [draft, isSaving, error, isSuccess];
}
