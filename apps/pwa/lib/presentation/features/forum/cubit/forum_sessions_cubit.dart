import 'package:flutter/foundation.dart';
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
  RealtimeChannel? _realtimeChannel;

  String get activeForumId => _resolvedForumId ?? forumId;
  DateTime? get activeForumCreatedAt => _resolvedForumCreatedAt ?? forumCreatedAt;

  ForumSessionsCubit({
    required this.forumId,
    this.forumCreatedAt,
    this.forumReference,
  }) : super(const ForumSessionsState());

  /// Sets up the Supabase Realtime Channel for client-to-client Broadcast mutations
  /// and PostgreSQL CDC table change listening.
  void setupRealtime() {
    if (_realtimeChannel != null) return;
    
    final fId = activeForumId;
    if (fId.isEmpty) return;

    final client = Supabase.instance.client;
    final channelName = 'forum_sessions_realtime_$fId';
    _realtimeChannel = client.channel(channelName);

    // 1. Listen for instant client Broadcast mutations
    _realtimeChannel!.onBroadcast(
      event: 'session_mutation',
      callback: (payload) {
        try {
          final action = payload['action'] as String?;
          final data = payload['session'] as Map<String, dynamic>?;
          if (data == null || action == null) return;

          final session = SessionModel.fromMap(data);

          if (action == 'insert') {
            _onSessionInserted(session);
          } else if (action == 'update') {
            _onSessionUpdated(session);
          } else if (action == 'delete') {
            _onSessionDeleted(session.id);
          }
        } catch (e) {
          debugPrint('[ForumSessionsCubit] Broadcast callback error: $e');
        }
      },
    );

    // 2. Listen to PostgreSQL CDC Changes (Absolute DB state source of truth)
    _realtimeChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'social',
      table: 'forum_sessions',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'forum_id',
        value: fId,
      ),
      callback: (payload) {
        try {
          if (payload.eventType == PostgresChangeEvent.insert) {
            final session = SessionModel.fromMap(payload.newRecord);
            _onSessionInserted(session);
          } else if (payload.eventType == PostgresChangeEvent.update) {
            final session = SessionModel.fromMap(payload.newRecord);
            _onSessionUpdated(session);
          } else if (payload.eventType == PostgresChangeEvent.delete) {
            final id = payload.oldRecord['id'] as String;
            _onSessionDeleted(id);
          }
        } catch (e) {
          debugPrint('[ForumSessionsCubit] CDC callback error: $e');
        }
      },
    );

    _realtimeChannel!.subscribe();
  }

  void _onSessionInserted(SessionModel session) {
    if (session.endsAt.isBefore(DateTime.now())) return;

    final exists = state.sessions.any((s) => s.id == session.id);
    if (!exists) {
      final updated = List<SessionModel>.from(state.sessions)..add(session);
      updated.sort((a, b) => a.startsAt.compareTo(b.startsAt));
      emit(state.copyWith(sessions: updated));
    }
  }

  void _onSessionUpdated(SessionModel session) {
    final index = state.sessions.indexWhere((s) => s.id == session.id);
    final updated = List<SessionModel>.from(state.sessions);

    if (session.endsAt.isBefore(DateTime.now())) {
      if (index != -1) {
        updated.removeAt(index);
        emit(state.copyWith(sessions: updated));
      }
      return;
    }

    if (index != -1) {
      updated[index] = session;
    } else {
      updated.add(session);
    }
    updated.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    emit(state.copyWith(sessions: updated));
  }

  void _onSessionDeleted(String sessionId) {
    final exists = state.sessions.any((s) => s.id == sessionId);
    if (exists) {
      final updated = state.sessions.where((s) => s.id != sessionId).toList();
      emit(state.copyWith(sessions: updated));
    }
  }

  void _broadcastMutation(String action, SessionModel session) {
    _realtimeChannel?.sendBroadcastMessage(
      event: 'session_mutation',
      payload: {
        'action': action,
        'session': {
          'id': session.id,
          'forum_id': session.forumId,
          'forum_created_at': session.forumCreatedAt?.toUtc().toIso8601String(),
          'starts_at': session.startsAt.toUtc().toIso8601String(),
          'ends_at': session.endsAt.toUtc().toIso8601String(),
          'sort_order': session.sortOrder,
          'info': {
            'title': session.title,
            'speakers': session.speakers,
            'room': session.room,
            'capacity': session.capacity,
          },
        },
      },
    );
  }

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
          .gte('ends_at', DateTime.now().toUtc().toIso8601String())
          .order('starts_at', ascending: true);

      final sessions = (response as List)
          .map((json) => SessionModel.fromMap(json as Map<String, dynamic>))
          .toList();

      emit(state.copyWith(sessions: sessions, isLoading: false));
      setupRealtime();
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
      
      final response = await Supabase.instance.client
          .from('forum_sessions')
          .insert(payload)
          .select()
          .single();

      final savedSession = SessionModel.fromMap(response);

      _onSessionInserted(savedSession);
      _broadcastMutation('insert', savedSession);

      emit(state.copyWith(isLoading: false));
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
      
      final response = await Supabase.instance.client
          .from('forum_sessions')
          .update(payload)
          .eq('id', session.id)
          .select()
          .single();

      final savedSession = SessionModel.fromMap(response);

      _onSessionUpdated(savedSession);
      _broadcastMutation('update', savedSession);

      emit(state.copyWith(isLoading: false));
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

      _onSessionDeleted(sessionId);
      
      _realtimeChannel?.sendBroadcastMessage(
        event: 'session_mutation',
        payload: {
          'action': 'delete',
          'session': {'id': sessionId},
        },
      );

      emit(state.copyWith(isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: 'Failed to delete session: $e'));
    }
  }

  @override
  Future<void> close() {
    _realtimeChannel?.unsubscribe();
    return super.close();
  }
}
