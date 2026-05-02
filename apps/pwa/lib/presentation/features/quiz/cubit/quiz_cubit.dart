import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'quiz_state.dart';

class QuizCubit extends Cubit<QuizState> {
  final String questionnaireId;
  final String userId;
  RealtimeChannel? _channel;
  Timer? _timer;

  QuizCubit({
    required this.questionnaireId,
    required this.userId,
    bool isHost = false,
  }) : super(QuizState(isHost: isHost));

  Future<void> init() async {
    try {
      // 1. Initial Fetch
      final data = await Supabase.instance.client
          .from('questionnaires')
          .select('*, forum_channel_id')
          .eq('id', questionnaireId)
          .single();

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
    _channel = Supabase.instance.client
        .channel('quiz_live_$questionnaireId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'questionnaires',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: questionnaireId,
          ),
          callback: (payload) {
            _handleUpdate(payload.newRecord);
          },
        )
        .subscribe();
  }

  Future<void> _handleUpdate(Map<String, dynamic> data) async {
    final newStatus = _mapStatus(data['quiz_state']);
    final newIndex = data['current_question_index'] as int? ?? -1;
    final expiresAt = data['state_expires_at'] as String?;

    // If question index changed or state moved to playing, fetch question
    if (newIndex != state.currentQuestionIndex || (newStatus == QuizStatus.playing && state.currentQuestion == null)) {
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
      final data = await Supabase.instance.client
          .from('questions')
          .select('*')
          .eq('questionnaire_id', questionnaireId)
          .eq('order_index', index)
          .single();
      
      emit(state.copyWith(currentQuestion: data));
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

    try {
      emit(state.copyWith(myAnswerIndex: optionIndex));

      await Supabase.instance.client
          .schema('responses')
          .from('responses')
          .insert({
        'questionnaire_id': questionnaireId,
        'user_id': userId,
        'answers': [optionIndex], // Store selected index in JSONB array
      });
    } catch (e) {
      // Revert if failed
      emit(state.copyWith(clearMyAnswer: true, errorMessage: "Failed to submit answer"));
      debugPrint('Error submitting answer: $e');
    }
  }

  Future<void> fetchLeaderboard() async {
    try {
      // Assuming a view or RPC for leaderboard
      final data = await Supabase.instance.client
          .rpc('get_quiz_leaderboard', params: {'p_quiz_id': questionnaireId});
      
      emit(state.copyWith(leaderboard: List<Map<String, dynamic>>.from(data)));
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

    await Supabase.instance.client
        .from('questionnaires')
        .update({
          'quiz_state': quizState,
          'current_question_index': questionIndex,
          'state_expires_at': expiresAt,
        })
        .eq('id', questionnaireId);
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
