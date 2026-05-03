import 'package:supabase_flutter/supabase_flutter.dart';

class QuizRepository {
  final SupabaseClient _client;
  QuizRepository(this._client);

  Future<Map<String, dynamic>> getQuestionnaire(
      String questionnaireId) async {
    return await _client
        .from('questionnaires')
        .select('*, forum_channel_id')
        .eq('id', questionnaireId)
        .single();
  }

  Future<Map<String, dynamic>?> getQuestion(
    String questionnaireId,
    int orderIndex,
  ) async {
    return await _client
        .from('questions')
        .select()
        .eq('questionnaire_id', questionnaireId)
        .eq('order_index', orderIndex)
        .maybeSingle();
  }

  Future<List<Map<String, dynamic>>> getLeaderboard(String quizId, {int limit = 5}) async {
    final data = await _client
        .rpc('get_quiz_leaderboard', params: {'p_quiz_id': quizId, 'p_limit': limit});
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
    await _client.schema('responses').from('responses').insert({
      'questionnaire_id': questionnaireId,
      'question_id': questionId,
      'user_id': userId,
      'selected_answer': selectedAnswer,
    });
  }

  Future<void> updateQuizState({
    required String questionnaireId,
    required String quizState,
    required int questionIndex,
    String? expiresAt,
  }) async {
    await _client.from('questionnaires').update({
      'quiz_state': quizState,
      'current_question_index': questionIndex,
      'state_expires_at': expiresAt,
    }).eq('id', questionnaireId);
  }

  RealtimeChannel subscribeToQuestionnaire(
    String questionnaireId,
    void Function(PostgresChangePayload) callback,
  ) {
    return _client
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
          callback: callback,
        );
  }
}
