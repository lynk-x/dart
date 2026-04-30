import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_core/core.dart';
import 'forum_sessions_state.dart';

class ForumSessionsCubit extends Cubit<ForumSessionsState> {
  final String eventId;

  ForumSessionsCubit({required this.eventId}) : super(const ForumSessionsState());

  Future<void> loadSessions() async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final response = await Supabase.instance.client
          .from('event_sessions')
          .select()
          .eq('event_id', eventId)
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
    try {
      await Supabase.instance.client.from('event_sessions').insert(session.toMap());
      await loadSessions();
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to add session: $e'));
    }
  }

  Future<void> updateSession(SessionModel session) async {
    try {
      await Supabase.instance.client
          .from('event_sessions')
          .update(session.toMap())
          .eq('id', session.id);
      await loadSessions();
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to update session: $e'));
    }
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      await Supabase.instance.client
          .from('event_sessions')
          .delete()
          .eq('id', sessionId);
      await loadSessions();
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to delete session: $e'));
    }
  }
}
