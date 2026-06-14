import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_core/core.dart';
import 'forum_sessions_state.dart';

class ForumSessionsCubit extends Cubit<ForumSessionsState> {
  final String forumId;
  final DateTime? forumCreatedAt;
  final String? forumReference;

  String? _resolvedForumId;
  DateTime? _resolvedForumCreatedAt;

  String get activeForumId => _resolvedForumId ?? forumId;
  DateTime? get activeForumCreatedAt => _resolvedForumCreatedAt ?? forumCreatedAt;

  ForumSessionsCubit({
    required this.forumId,
    this.forumCreatedAt,
    this.forumReference,
  }) : super(const ForumSessionsState());

  Future<void> loadSessions() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      if (activeForumId.isEmpty && forumReference != null && forumReference!.isNotEmpty) {
        final forumRes = await Supabase.instance.client
            .from('forums')
            .select('id, created_at')
            .eq('reference', forumReference!)
            .maybeSingle();
        if (forumRes != null) {
          _resolvedForumId = forumRes['id'] as String;
          _resolvedForumCreatedAt = DateTime.parse(forumRes['created_at'] as String);
        }
      }

      if (activeForumId.isEmpty) {
        throw Exception('Forum not found or reference is invalid.');
      }

      final response = await Supabase.instance.client
          .from('forum_sessions')
          .select()
          .eq('forum_id', activeForumId)
          .order('starts_at', ascending: true);

      final sessions = (response as List)
          .map((json) => SessionModel.fromMap(json as Map<String, dynamic>))
          .toList();

      emit(state.copyWith(sessions: sessions, isLoading: false));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load sessions: $e',
      ));
    }
  }

  Future<void> addSession(SessionModel session) async {
    emit(state.copyWith(isLoading: true, clearError: true));

    try {
      final payload = session.toMap()..remove('id');
      payload['forum_id'] = activeForumId;
      payload['forum_created_at'] = activeForumCreatedAt?.toIso8601String();
      await Supabase.instance.client
          .from('forum_sessions')
          .insert(payload);
      await loadSessions();
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: 'Failed to add session: $e'));
    }
  }

  Future<void> updateSession(SessionModel session) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final payload = session.toMap();
      payload['forum_id'] = activeForumId;
      payload['forum_created_at'] = activeForumCreatedAt?.toIso8601String();
      await Supabase.instance.client
          .from('forum_sessions')
          .update(payload)
          .eq('id', session.id);
      await loadSessions();
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: 'Failed to update session: $e'));
    }
  }

  Future<void> deleteSession(String sessionId) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      await Supabase.instance.client
          .from('forum_sessions')
          .delete()
          .eq('id', sessionId);
      await loadSessions();
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: 'Failed to delete session: $e'));
    }
  }
}
