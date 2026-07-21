import 'package:supabase_flutter/supabase_flutter.dart';

/// Quiz/poll data access. All reads go through the `api.v1_*` views and all
/// writes through `api.*` RPCs — the `surveys` schema is not PostgREST-exposed.
/// A poll/quiz IS its announcing forum_messages row (message_id below is
/// always that message's id) — see `surveys.polls` / `surveys.quiz_sessions`.
/// `v1_questions.correct_options` is null until the quiz moves past 'playing'
/// (reveal/leaderboard/podium/finished); scoring itself always happens
/// server-side in `api.submit_survey_response`'s insert triggers.
class QuizRepository {
  final SupabaseClient _client;
  QuizRepository(this._client);

  Future<Map<String, dynamic>> getPoll(String messageId) async {
    return await _client
        .schema('api')
        .from('v1_polls')
        .select()
        .eq('message_id', messageId)
        .single();
  }

  Future<Map<String, dynamic>> getQuizSession(String messageId) async {
    return await _client
        .schema('api')
        .from('v1_quiz_sessions')
        .select()
        .eq('message_id', messageId)
        .single();
  }

  Future<Map<String, dynamic>?> getQuestion(
    String messageId,
    int orderIndex,
  ) async {
    return await _client
        .schema('api')
        .from('v1_questions')
        .select()
        .eq('message_id', messageId)
        .eq('order_index', orderIndex)
        .maybeSingle();
  }

  Future<List<Map<String, dynamic>>> getLeaderboard(String quizId,
      {int limit = 5}) async {
    final data = await _client.schema('api').rpc('get_quiz_leaderboard',
        params: {'p_quiz_id': quizId, 'p_limit': limit});
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Map<String, dynamic>>> getLeaderboardLive(
    String messageId, {
    int limit = 20,
  }) async {
    final data = await _client
        .schema('api')
        .from('v1_quiz_leaderboard')
        .select(
            'user_id, display_name, avatar_url, total_score, answers_count, last_answered_at')
        .eq('message_id', messageId)
        .order('total_score', ascending: false)
        .order('last_answered_at', ascending: true)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> submitAnswer({
    required String messageId,
    required String questionId,
    required String userId,
    required List<int> selectedAnswer,
  }) async {
    // account_id resolution, published check and per-question dedupe all
    // happen server-side; userId is derived from the session there too.
    await _client.schema('api').rpc('submit_survey_response', params: {
      'p_message_id': messageId,
      'p_question_id': questionId,
      'p_selected_answer': selectedAnswer,
    });
  }

  Future<void> updateQuizState({
    required String messageId,
    required String quizState,
    required int questionIndex,
    String? expiresAt,
    // Only meaningful (and only applied) on the lobby -> playing transition;
    // the RPC ignores it otherwise. Randomizes surveys.questions.order_index
    // once, server-side, so every player sees the same shuffled order.
    bool shuffleQuestions = false,
  }) async {
    await _client.schema('api').rpc('update_quiz_state', params: {
      'p_message_id': messageId,
      'p_quiz_state': quizState,
      'p_question_index': questionIndex,
      'p_expires_at': expiresAt,
      'p_shuffle_questions': shuffleQuestions,
    });
  }

  RealtimeChannel subscribeToQuizSession(
    String messageId,
    void Function(PostgresChangePayload) callback,
  ) {
    return _client.channel('quiz_live_$messageId').onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'surveys',
          table: 'quiz_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'message_id',
            value: messageId,
          ),
          callback: callback,
        );
  }

  /// Atomically creates the announcing forum_messages row and its poll
  /// config + single question. Returns the new message id. messageType must
  /// be 'livechat_poll' or 'update_poll'.
  Future<String> createPoll(Map<String, dynamic> params) async {
    final result = await _client
        .schema('api')
        .rpc('create_poll', params: params) as Map<String, dynamic>;
    return result['message_id'] as String;
  }

  /// Atomically creates the announcing forum_messages row, its quiz_sessions
  /// config, and all its questions. Returns the new message id. messageType
  /// must be 'livechat_quiz' or 'update_quiz'.
  Future<String> createQuiz(Map<String, dynamic> params) async {
    final result = await _client
        .schema('api')
        .rpc('create_quiz', params: params) as Map<String, dynamic>;
    return result['message_id'] as String;
  }
}
