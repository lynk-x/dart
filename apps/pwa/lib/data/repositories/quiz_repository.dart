import 'package:supabase_flutter/supabase_flutter.dart';

/// Quiz/poll data access. All reads go through the `api.v1_*` views and all
/// writes through `api.*` RPCs — the `surveys` schema is not PostgREST-exposed.
/// A poll/quiz (surveys.questionnaires) has its own independent id and can
/// exist as an unpublished draft with no announcing forum_messages row at
/// all — questionnaireId below is always that independent id, never a
/// message id. Publishing (creating the message, see publishQuestionnaire)
/// is a separate step from creation. `v1_questions.correct_options` is null
/// until the quiz moves past 'playing' (reveal/leaderboard/podium/finished);
/// scoring itself always happens server-side in
/// `api.submit_survey_response`'s insert triggers.
class QuizRepository {
  final SupabaseClient _client;
  QuizRepository(this._client);

  Future<Map<String, dynamic>> getQuestionnaire(String questionnaireId) async {
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

  Future<List<Map<String, dynamic>>> getLeaderboard(String questionnaireId,
      {int limit = 5}) async {
    final data = await _client.schema('api').rpc('get_quiz_leaderboard',
        params: {'p_questionnaire_id': questionnaireId, 'p_limit': limit});
    return List<Map<String, dynamic>>.from(data as List);
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
    // Only meaningful (and only applied) on the lobby -> playing transition;
    // the RPC ignores it otherwise. Randomizes surveys.questions.order_index
    // once, server-side, so every player sees the same shuffled order.
    bool shuffleQuestions = false,
  }) async {
    await _client.schema('api').rpc('update_quiz_state', params: {
      'p_questionnaire_id': questionnaireId,
      'p_quiz_state': quizState,
      'p_question_index': questionIndex,
      'p_expires_at': expiresAt,
      'p_shuffle_questions': shuffleQuestions,
    });
  }

  RealtimeChannel subscribeToQuizSession(
    String questionnaireId,
    void Function(PostgresChangePayload) callback,
  ) {
    return _client.channel('quiz_live_$questionnaireId').onPostgresChanges(
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

  /// Creates a DRAFT poll: a surveys.questionnaires row (type='poll') plus
  /// its single question — no forum_messages row yet. Call
  /// publishQuestionnaire separately to post it to the forum.
  Future<String> createPoll(Map<String, dynamic> params) async {
    final result = await _client
        .schema('api')
        .rpc('create_poll', params: params) as Map<String, dynamic>;
    return result['questionnaire_id'] as String;
  }

  /// Creates a DRAFT quiz: a surveys.questionnaires row (type='quiz') plus
  /// all its questions — no forum_messages row yet. Call
  /// publishQuestionnaire separately to post it to the forum.
  Future<String> createQuiz(Map<String, dynamic> params) async {
    final result = await _client
        .schema('api')
        .rpc('create_quiz', params: params) as Map<String, dynamic>;
    return result['questionnaire_id'] as String;
  }

  /// Updates an existing DRAFT poll in place — same param shape as
  /// createPoll, plus p_questionnaire_id. Only draft rows are editable this
  /// way; the RPC raises if the poll has already been published.
  Future<String> updatePollDraft(
    String questionnaireId,
    Map<String, dynamic> params,
  ) async {
    final result = await _client.schema('api').rpc('update_poll_draft',
        params: {'p_questionnaire_id': questionnaireId, ...params}) as Map<String, dynamic>;
    return result['questionnaire_id'] as String;
  }

  /// Updates an existing DRAFT quiz in place — same param shape as
  /// createQuiz, plus p_questionnaire_id. Replaces all of its questions
  /// (delete + reinsert) rather than diffing, matching how the builder form
  /// always sends the complete current question list. Only draft rows are
  /// editable this way; the RPC raises if the quiz has already been
  /// published.
  Future<String> updateQuizDraft(
    String questionnaireId,
    Map<String, dynamic> params,
  ) async {
    final result = await _client.schema('api').rpc('update_quiz_draft',
        params: {'p_questionnaire_id': questionnaireId, ...params}) as Map<String, dynamic>;
    return result['questionnaire_id'] as String;
  }

  /// Publishes a draft: atomically creates the announcing forum_messages row
  /// and flips the questionnaire to 'published'. Returns the new message's
  /// id + created_at — the RPC does not broadcast a realtime event (unlike
  /// sendMessage()), so the caller needs both to build a local optimistic
  /// ChatMessage itself. messageType must match the questionnaire's type
  /// ('livechat_poll'/'update_poll' for a poll, 'livechat_quiz'/
  /// 'update_quiz' for a quiz).
  Future<({String messageId, DateTime createdAt})> publishQuestionnaire({
    required String questionnaireId,
    String? channelId,
    String? channelCreatedAt,
    required String content,
    required String messageType,
  }) async {
    final result = await _client.schema('api').rpc('publish_questionnaire', params: {
      'p_questionnaire_id': questionnaireId,
      'p_channel_id': channelId,
      'p_channel_created_at': channelCreatedAt,
      'p_content': content,
      'p_message_type': messageType,
    }) as Map<String, dynamic>;
    return (
      messageId: result['message_id'] as String,
      createdAt: DateTime.parse(result['created_at'] as String),
    );
  }

  Future<List<Map<String, dynamic>>> getForumQuizList(String forumId) async {
    final data = await _client.schema('api').rpc('get_forum_quiz_list',
        params: {'p_forum_id': forumId});
    return List<Map<String, dynamic>>.from(data as List);
  }
}
