import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/data/repositories/quiz_repository.dart';
import '../models/quiz_builder_model.dart';
import 'quiz_builder_state.dart';

class QuizBuilderCubit extends Cubit<QuizBuilderState> {
  final QuizRepository _repo;
  final String? channelId;
  final String? channelCreatedAt;

  QuizBuilderCubit({
    required QuizRepository repo,
    required String forumId,
    this.channelId,
    this.channelCreatedAt,
    // Set when editing an already-saved draft (e.g. reopened from
    // QuizListScreen's "Drafts" section) rather than starting fresh — lets
    // saveDraft() update the existing row instead of creating a new one.
    String? questionnaireId,
  })  : _repo = repo,
        super(QuizBuilderState(
          questionnaireId: questionnaireId,
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

  /// Pre-fills the builder from a past quiz (draft, live, or finished) —
  /// used by both "Duplicate" (questionnaireId left null, so saveDraft()
  /// creates a brand new row) and "resume editing a draft" (caller passes
  /// this cubit a questionnaireId at construction so saveDraft() updates the
  /// existing row instead).
  void loadFromHistory(Map<String, dynamic> quiz) {
    final questions = (quiz['questions'] as List<dynamic>? ?? [])
        .map((q) => q as Map<String, dynamic>)
        .map((q) {
      final correct = (q['correct'] as Map<String, dynamic>? ?? {});
      return DraftQuestion(
        text: q['question_text'] as String? ?? '',
        options: List<String>.from(q['options'] as List<dynamic>? ?? []),
        correctIndices: correct.keys.map(int.parse).toList(),
      );
    }).toList();

    emit(state.copyWith(
      draft: state.draft.copyWith(
        title: quiz['title'] as String? ?? '',
        type: 'quiz',
        questions: questions,
        timePerQuestionSeconds: quiz['time_per_question_seconds'] as int?,
        scoringMode:
            QuizScoringMode.fromValue(quiz['scoring_mode'] as String?),
        shuffleAnswers: quiz['shuffle_answers'] as bool?,
        shuffleQuestions: quiz['shuffle_questions'] as bool?,
        revealAnswer: quiz['reveal_answer'] as bool?,
      ),
    ));
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

  /// Saves the current draft — creates a new surveys.questionnaires row the
  /// first time (state.questionnaireId is null), or updates the existing
  /// one in place on every save after that (e.g. reopened via "Preview"/
  /// "resume draft", which passes questionnaireId at construction — see the
  /// constructor's own doc comment). Without the update branch, saving an
  /// already-saved draft again silently created a second, orphaned row.
  /// No forum_messages row is touched either way. This is the LiveQuiz
  /// builder's primary "checkmark" action — it never publishes on its own;
  /// publish() is a separate, explicit step.
  Future<void> saveDraft() async {
    final validationError = _validate();
    if (validationError != null) {
      emit(state.copyWith(error: validationError));
      return;
    }

    emit(state.copyWith(isSaving: true, error: null));
    try {
      final existingId = state.questionnaireId;
      final String id;
      if (existingId == null) {
        id = state.draft.type == 'poll'
            ? await _repo.createPoll(state.draft.toCreatePollParams())
            : await _repo.createQuiz(state.draft.toCreateQuizParams());
      } else {
        id = state.draft.type == 'poll'
            ? await _repo.updatePollDraft(existingId, state.draft.toCreatePollParams())
            : await _repo.updateQuizDraft(existingId, state.draft.toCreateQuizParams());
      }
      emit(state.copyWith(
        isSaving: false,
        isDraftSaved: true,
        questionnaireId: id,
      ));
    } catch (e) {
      emit(state.copyWith(isSaving: false, error: e.toFriendlyMessage()));
    }
  }

  /// Publishes an already-saved draft: creates the announcing forum_messages
  /// row and flips the questionnaire to 'published', atomically, via
  /// api.publish_questionnaire. Requires saveDraft() (or a
  /// questionnaireId passed at construction) to have run first.
  /// [messageType] must be one of livechat_poll/livechat_quiz/update_poll/
  /// update_quiz, matching which tab launched the composer.
  Future<void> publish(String messageType) async {
    final id = state.questionnaireId;
    if (id == null) {
      emit(state.copyWith(error: 'Save this as a draft before publishing.'));
      return;
    }

    emit(state.copyWith(isSaving: true, error: null));
    try {
      final result = await _repo.publishQuestionnaire(
        questionnaireId: id,
        channelId: channelId,
        channelCreatedAt: channelCreatedAt,
        content: state.draft.title,
        messageType: messageType,
      );
      emit(state.copyWith(
        isSaving: false,
        isPublished: true,
        publishedMessageId: result.messageId,
        publishedMessageCreatedAt: result.createdAt,
      ));
    } catch (e) {
      emit(state.copyWith(isSaving: false, error: e.toFriendlyMessage()));
    }
  }

  /// Convenience for flows with no separate draft step in their UI (today:
  /// PollCardEditor's single "Post Poll" button) — saves the draft then
  /// immediately publishes it in one call.
  Future<void> saveDraftAndPublish(String messageType) async {
    await saveDraft();
    if (state.questionnaireId == null || state.error != null) return;
    await publish(messageType);
  }
}
