import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_x/data/repositories/quiz_repository.dart';
import '../models/quiz_builder_model.dart';
import 'quiz_builder_state.dart';

class QuizBuilderCubit extends Cubit<QuizBuilderState> {
  final QuizRepository _repo;

  QuizBuilderCubit({
    required QuizRepository repo,
    required String forumId,
    String? channelId,
    String? channelCreatedAt,
  })  : _repo = repo,
        super(QuizBuilderState(
          draft: DraftQuiz(
            forumId: forumId,
            channelId: channelId,
            channelCreatedAt: channelCreatedAt,
            title: '',
            info: '',
          ),
        ));

  void updateSettings(String title, String info, String type) {
    emit(state.copyWith(
      draft: state.draft.copyWith(title: title, info: info, type: type),
    ));
  }

  void updateGameConfig({
    int? timePerQuestionSeconds,
    QuizScoringMode? scoringMode,
    bool? shuffleAnswers,
    bool? shuffleQuestions,
    bool? revealAnswer,
  }) {
    emit(state.copyWith(
      draft: state.draft.copyWith(
        timePerQuestionSeconds: timePerQuestionSeconds,
        scoringMode: scoringMode,
        shuffleAnswers: shuffleAnswers,
        shuffleQuestions: shuffleQuestions,
        revealAnswer: revealAnswer,
      ),
    ));
  }

  void addQuestion() {
    final updatedQuestions = List<DraftQuestion>.from(state.draft.questions)
      ..add(const DraftQuestion());
    emit(state.copyWith(
        draft: state.draft.copyWith(questions: updatedQuestions)));
  }

  void removeQuestion(int index) {
    final updatedQuestions = List<DraftQuestion>.from(state.draft.questions)
      ..removeAt(index);
    emit(state.copyWith(
        draft: state.draft.copyWith(questions: updatedQuestions)));
  }

  void updateQuestionText(int index, String text) {
    final updatedQuestions = List<DraftQuestion>.from(state.draft.questions);
    updatedQuestions[index] = updatedQuestions[index].copyWith(text: text);
    emit(state.copyWith(
        draft: state.draft.copyWith(questions: updatedQuestions)));
  }

  void addOption(int qIndex) {
    final updatedQuestions = List<DraftQuestion>.from(state.draft.questions);
    final currentQ = updatedQuestions[qIndex];
    final newOptions = List<String>.from(currentQ.options)..add('');
    updatedQuestions[qIndex] = currentQ.copyWith(options: newOptions);
    emit(state.copyWith(
        draft: state.draft.copyWith(questions: updatedQuestions)));
  }

  void removeOption(int qIndex, int oIndex) {
    final updatedQuestions = List<DraftQuestion>.from(state.draft.questions);
    final currentQ = updatedQuestions[qIndex];
    if (currentQ.options.length <= 2) return; // Enforce minimum 2 options

    final newOptions = List<String>.from(currentQ.options)..removeAt(oIndex);
    // Remove if correct index was deleted and shift indices
    final newCorrectIndices = currentQ.correctIndices
        .where((i) => i != oIndex)
        .map((i) => i > oIndex ? i - 1 : i)
        .toList();

    updatedQuestions[qIndex] = currentQ.copyWith(
      options: newOptions,
      correctIndices: newCorrectIndices,
    );
    emit(state.copyWith(
        draft: state.draft.copyWith(questions: updatedQuestions)));
  }

  void updateOptionText(int qIndex, int oIndex, String text) {
    final updatedQuestions = List<DraftQuestion>.from(state.draft.questions);
    final currentQ = updatedQuestions[qIndex];
    final newOptions = List<String>.from(currentQ.options);
    newOptions[oIndex] = text;
    updatedQuestions[qIndex] = currentQ.copyWith(options: newOptions);
    emit(state.copyWith(
        draft: state.draft.copyWith(questions: updatedQuestions)));
  }

  void toggleCorrectOption(int qIndex, int oIndex) {
    final updatedQuestions = List<DraftQuestion>.from(state.draft.questions);
    final currentQ = updatedQuestions[qIndex];
    List<int> newCorrectIndices;

    if (state.draft.type == 'quiz') {
      // In MVP, a quiz might have single correct answers or multiple. We'll support multiple.
      newCorrectIndices = List<int>.from(currentQ.correctIndices);
      if (newCorrectIndices.contains(oIndex)) {
        newCorrectIndices.remove(oIndex);
      } else {
        newCorrectIndices.add(oIndex);
      }
    } else {
      // Polls don't have correct answers.
      newCorrectIndices = [];
    }

    updatedQuestions[qIndex] =
        currentQ.copyWith(correctIndices: newCorrectIndices);
    emit(state.copyWith(
        draft: state.draft.copyWith(questions: updatedQuestions)));
  }

  void reorderQuestions(int oldIndex, int newIndex) {
    final updatedQuestions = List<DraftQuestion>.from(state.draft.questions);
    final item = updatedQuestions.removeAt(oldIndex);
    updatedQuestions.insert(newIndex, item);
    emit(state.copyWith(
        draft: state.draft.copyWith(questions: updatedQuestions)));
  }

  String? _validate() {
    if (state.draft.title.trim().isEmpty) return 'Quiz title is required.';
    if (state.draft.questions.isEmpty) {
      return 'Quiz must have at least 1 question.';
    }
    for (var i = 0; i < state.draft.questions.length; i++) {
      final q = state.draft.questions[i];
      if (q.text.trim().isEmpty) return 'Question ${i + 1} is empty.';
      if (q.options.length < 2) {
        return 'Question ${i + 1} must have at least 2 options.';
      }
      if (q.options.any((o) => o.trim().isEmpty)) {
        return 'Question ${i + 1} has empty options.';
      }
      if (state.draft.type == 'quiz' && q.correctIndices.isEmpty) {
        return 'Question ${i + 1} must have at least 1 correct answer.';
      }
    }
    return null;
  }

  /// Publishes immediately — there is no draft-save/reopen flow, so this
  /// always creates a published poll/quiz. [messageType] must be one of
  /// livechat_poll/livechat_quiz/update_poll/update_quiz, matching which tab
  /// launched the composer.
  Future<void> publish(String messageType) async {
    final validationError = _validate();
    if (validationError != null) {
      emit(state.copyWith(error: validationError));
      return;
    }

    emit(state.copyWith(isSaving: true, error: null, isSuccess: false));
    try {
      if (state.draft.type == 'poll') {
        await _repo
            .createPoll(state.draft.toCreatePollParams(messageType: messageType));
      } else {
        await _repo
            .createQuiz(state.draft.toCreateQuizParams(messageType: messageType));
      }
      emit(state.copyWith(isSaving: false, isSuccess: true));
    } catch (e) {
      emit(state.copyWith(isSaving: false, error: e.toString()));
    }
  }
}
