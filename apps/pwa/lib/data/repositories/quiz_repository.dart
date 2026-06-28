import 'package:supabase_flutter/supabase_flutter.dart';

class QuizRepository {
  final SupabaseClient _client;
  QuizRepository(this._client);

  Future<Map<String, dynamic>> getQuestionnaire(
      String questionnaireId) async {
    return await _client
        .schema('surveys')
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
        .schema('surveys')
        .from('questions')
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
    await _client.schema('surveys').from('responses').insert({
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
    await _client.schema('surveys').from('questionnaires').update({
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
    
    // 1. Upsert Questionnaire
    final response = await _client
        .schema('surveys')
        .from('questionnaires')
        .upsert(quizData)
        .select('id')
        .single();
    
    final questionnaireId = response['id'];

    // 2. Clear old questions to replace them
    await _client
        .schema('surveys')
        .from('questions')
        .delete()
        .eq('questionnaire_id', questionnaireId);

    // 3. Insert new questions
    if (questionsData.isNotEmpty) {
      final questionsToInsert = questionsData.asMap().entries.map((entry) {
        final index = entry.key;
        final q = entry.value as Map<String, dynamic>;
        // Map correctIndices list to JSON object e.g. {"0": true, "1": true}
        final correctIndices = q['correct'] as List<dynamic>;
        final correctMap = {
          for (var i in correctIndices) i.toString(): true
        };
        
        return {
          if (q['id'] != null) 'id': q['id'],
          'questionnaire_id': questionnaireId,
          'order_index': index,
          'question_text': q['question_text'],
          'options': q['options'],
          'correct': correctMap,
        };
      }).toList();

      await _client
          .schema('surveys')
          .from('questions')
          .insert(questionsToInsert);
    }
  }
}
