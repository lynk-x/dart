import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/data/repositories/repositories.dart';
import 'quiz_state.dart';

class QuizCubit extends Cubit<QuizState> {
  final String questionnaireId;
  final String userId;
  final QuizRepository _repo;
  RealtimeChannel? _channel;
  Timer? _timer;

  QuizCubit({
    required this.questionnaireId,
    required this.userId,
    required QuizRepository repo,
    bool isHost = false,
  })  : _repo = repo,
        super(QuizState(isHost: isHost));

  Future<void> init() async {
    try {
      // 1. Initial Fetch
      final data = await _repo.getQuestionnaire(questionnaireId);

      emit(state.copyWith(
        status: _mapStatus(data['quiz_state']),
        questionnaire: data,
        currentQuestionIndex: data['current_question_index'] ?? -1,
      ));

      // 2. Setup Realtime
      _setupRealtimeListener();

      // 3. Initial sync if already playing
      if (state.status == QuizStatus.playing || state.status == QuizStatus.reveal) {
        await _fetchCurrentQuestion(state.currentQuestionIndex);
        _startLocalTimer(data['state_expires_at']);
      }

      if (state.status == QuizStatus.leaderboard || state.status == QuizStatus.podium) {
        await fetchLeaderboard();
      }
    } catch (e) {
      emit(state.copyWith(status: QuizStatus.error, errorMessage: e.toString()));
    }
  }

  void _setupRealtimeListener() {
    _channel = _repo.subscribeToQuestionnaire(questionnaireId, (payload) {
      _handleUpdate(payload.newRecord);
    }).subscribe();
  }

  Future<void> _handleUpdate(Map<String, dynamic> data) async {
    final newStatus = _mapStatus(data['quiz_state']);
    final newIndex = data['current_question_index'] as int? ?? -1;
    final expiresAt = data['state_expires_at'] as String?;

    // If question index changed or state moved to playing, fetch question
    if (newIndex != state.currentQuestionIndex ||
        (newStatus == QuizStatus.playing && state.currentQuestion == null)) {
      await _fetchCurrentQuestion(newIndex);
    }

    if (newStatus == QuizStatus.leaderboard || newStatus == QuizStatus.podium) {
      await fetchLeaderboard();
    }

    emit(state.copyWith(
      status: newStatus,
      currentQuestionIndex: newIndex,
      clearMyAnswer: newIndex != state.currentQuestionIndex, // Clear selection on new question
    ));

    _startLocalTimer(expiresAt);
  }

  Future<void> _fetchCurrentQuestion(int index) async {
    if (index < 0) return;
    try {
      final data = await _repo.getQuestion(questionnaireId, index);
      if (data != null) {
        emit(state.copyWith(currentQuestion: data));
      }
    } catch (e) {
      debugPrint('Error fetching question: $e');
    }
  }

  void _startLocalTimer(String? expiresAtStr) {
    _timer?.cancel();
    if (expiresAtStr == null) return;

    final expiresAt = DateTime.parse(expiresAtStr);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now().toUtc();
      final diff = expiresAt.difference(now).inSeconds;

      if (diff <= 0) {
        emit(state.copyWith(timeLeft: 0));
        timer.cancel();
      } else {
        emit(state.copyWith(timeLeft: diff));
      }
    });
  }

  Future<void> submitAnswer(int optionIndex) async {
    if (state.status != QuizStatus.playing || state.myAnswerIndex != null) return;

    final question = state.currentQuestion;
    final questionId = question?['id'] as String?;
    if (questionId == null) {
      debugPrint('[QuizCubit] submitAnswer: no current question loaded');
      return;
    }

    try {
      // responses.responses columns: question_id NOT NULL, selected_answer jsonb
      // (array of indices). The legacy 'answers' name was wrong.
      await _repo.submitAnswer(
        questionnaireId: questionnaireId,
        questionId: questionId,
        userId: userId,
        selectedAnswer: [optionIndex],
      );
      // Only record the answer locally after the server confirms it, so the
      // UI never shows an answer as submitted when the RPC failed.
      emit(state.copyWith(myAnswerIndex: optionIndex));
    } catch (e) {
      emit(state.copyWith(clearMyAnswer: true, errorMessage: "Failed to submit answer"));
      debugPrint('Error submitting answer: $e');
    }
  }

  Future<void> fetchLeaderboard() async {
    try {
      final data = await _repo.getLeaderboard(questionnaireId);
      emit(state.copyWith(leaderboard: data));
    } catch (e) {
      debugPrint('Error fetching leaderboard: $e');
    }
  }

  // --- Host Controls ---

  Future<void> startQuiz() async {
    if (!state.isHost) return;
    await _updateRemoteState('playing', 0, 30); // 30s for first question
  }

  Future<void> nextQuestion() async {
    if (!state.isHost) return;

    // Check if there are more questions
    final questionsCount = state.questionnaire?['info']?['questions_count'] as int? ?? 0;
    final nextIndex = state.currentQuestionIndex + 1;

    if (nextIndex >= questionsCount) {
      await showPodium();
    } else {
      await _updateRemoteState('playing', nextIndex, 30);
    }
  }

  Future<void> showLeaderboard() async {
    if (!state.isHost) return;
    await _updateRemoteState('leaderboard', state.currentQuestionIndex, 0);
  }

  Future<void> showPodium() async {
    if (!state.isHost) return;
    await _updateRemoteState('podium', state.currentQuestionIndex, 0);
  }

  Future<void> closeQuiz() async {
    if (!state.isHost) return;
    await _updateRemoteState('finished', state.currentQuestionIndex, 0);
  }

  Future<void> _updateRemoteState(String quizState, int questionIndex, int seconds) async {
    final expiresAt = seconds > 0
        ? DateTime.now().toUtc().add(Duration(seconds: seconds)).toIso8601String()
        : null;

    await _repo.updateQuizState(
      questionnaireId: questionnaireId,
      quizState: quizState,
      questionIndex: questionIndex,
      expiresAt: expiresAt,
    );
  }

  QuizStatus _mapStatus(String? status) {
    switch (status) {
      case 'lobby': return QuizStatus.lobby;
      case 'playing': return QuizStatus.playing;
      case 'reveal': return QuizStatus.reveal;
      case 'leaderboard': return QuizStatus.leaderboard;
      case 'podium': return QuizStatus.podium;
      case 'finished': return QuizStatus.finished;
      default: return QuizStatus.lobby;
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    _channel?.unsubscribe();
    return super.close();
  }
}
