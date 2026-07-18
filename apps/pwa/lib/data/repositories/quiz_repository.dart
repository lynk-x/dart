import 'package:supabase_flutter/supabase_flutter.dart';

/// Quiz/poll data access. All reads go through the `api.v1_*` views and all
/// writes through `api.*` RPCs — the `surveys` schema is not PostgREST-exposed.
/// `v1_questions.correct_options` is null until the questionnaire moves past
/// 'playing' (reveal/leaderboard/podium/finished); scoring itself always
/// happens server-side in `api.submit_survey_response`'s insert triggers.
class QuizRepository {
  final SupabaseClient _client;
  QuizRepository(this._client);

  Future<Map<String, dynamic>> getQuestionnaire(
      String questionnaireId) async {
    return await _client
        .schema('api')
        .from('v1_questionnaires')
        .select()
        .eq('id', questionnaireId)
        .single();
  }

  Future<Map<String, dynamic>?> getQuestion(
    String questionnaireId,
    int orderIndex,
  ) async {
    return await _client
        .schema('api')
        .from('v1_questions')
        .select()
        .eq('questionnaire_id', questionnaireId)
        .eq('order_index', orderIndex)
        .maybeSingle();
  }

  Future<List<Map<String, dynamic>>> getLeaderboard(String quizId, {int limit = 5}) async {
    final data = await _client
        .schema('api').rpc('get_quiz_leaderboard', params: {'p_quiz_id': quizId, 'p_limit': limit});
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Map<String, dynamic>>> getLeaderboardLive(
    String questionnaireId, {
    int limit = 20,
  }) async {
    final data = await _client
        .schema('api')
        .from('v1_quiz_leaderboard')
        .select('user_id, display_name, avatar_url, total_score, answers_count, last_answered_at')
        .eq('questionnaire_id', questionnaireId)
        .order('total_score', ascending: false)
        .order('last_answered_at', ascending: true)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> submitAnswer({
    required String questionnaireId,
    required String questionId,
    required String userId,
    required List<int> selectedAnswer,
  }) async {
    // account_id resolution, published check and per-question dedupe all
    // happen server-side; userId is derived from the session there too.
    await _client.schema('api').rpc('submit_survey_response', params: {
      'p_questionnaire_id': questionnaireId,
      'p_question_id': questionId,
      'p_selected_answer': selectedAnswer,
    });
  }

  Future<void> updateQuizState({
    required String questionnaireId,
    required String quizState,
    required int questionIndex,
    String? expiresAt,
  }) async {
    await _client.schema('api').rpc('update_quiz_state', params: {
      'p_questionnaire_id': questionnaireId,
      'p_quiz_state': quizState,
      'p_question_index': questionIndex,
      'p_expires_at': expiresAt,
    });
  }

  RealtimeChannel subscribeToQuestionnaire(
    String questionnaireId,
    void Function(PostgresChangePayload) callback,
  ) {
    return _client
        .channel('quiz_live_$questionnaireId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'surveys',
          table: 'questionnaires',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: questionnaireId,
          ),
          callback: callback,
        );
  }

  Future<void> saveQuiz(Map<String, dynamic> quizData) async {
    final questionsData = quizData.remove('questions') as List<dynamic>;

    // Map each question's correctIndices list to the JSON object shape the
    // server stores, e.g. {"0": true, "1": true}.
    final questionsPayload = questionsData.map((raw) {
      final q = raw as Map<String, dynamic>;
      final correctIndices = q['correct'] as List<dynamic>;
      return {
        if (q['id'] != null) 'id': q['id'],
        'question_text': q['question_text'],
        'options': q['options'],
        'correct': {for (var i in correctIndices) i.toString(): true},
      };
    }).toList();

    await _client.schema('api').rpc('save_quiz', params: {
      'p_quiz': quizData,
      'p_questions': questionsPayload,
    });
  }
}
