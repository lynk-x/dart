import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/data/repositories/forum_repository.dart';
import 'package:lynk_x/presentation/features/forum/services/forum_broadcast_service.dart';
import 'forum_sessions_state.dart';

class ForumSessionsCubit extends Cubit<ForumSessionsState> {
  final String forumId;
  final DateTime? forumCreatedAt;
  final String? forumReference;
  final ForumRepository _repo;

  String? _resolvedForumId;
  DateTime? _resolvedForumCreatedAt;
  String? _realtimeForumId;
  ForumBroadcastListener? _sessionBroadcastListener;
  ForumBroadcastListener? _sessionDbListener;

  String get activeForumId => _resolvedForumId ?? forumId;
  DateTime? get activeForumCreatedAt =>
      _resolvedForumCreatedAt ?? forumCreatedAt;

  ForumSessionsCubit({
    required this.forumId,
    required ForumRepository repo,
    this.forumCreatedAt,
    this.forumReference,
  })  : _repo = repo,
        super(const ForumSessionsState());

  /// Subscribes to multiplexed `forum:$fId` Broadcast events for instant
  /// optimistic client mutations and DB-trigger session updates.
  void setupRealtime() {
    if (_realtimeForumId != null) return;

    final fId = activeForumId;
    if (fId.isEmpty) return;

    _realtimeForumId = fId;

    // 1. Listen for instant client Broadcast mutations
    _sessionBroadcastListener = (payload) {
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
    };

    // 2. Listen to server Broadcast from Database trigger (source of truth)
    _sessionDbListener = (payload) {
      try {
        final op = payload['operation'] as String?;
        final data = payload['record'] as Map<String, dynamic>?;
        final oldData = payload['old_record'] as Map<String, dynamic>?;

        if (op == 'INSERT' && data != null) {
          _onSessionInserted(SessionModel.fromMap(data));
        } else if (op == 'UPDATE' && data != null) {
          _onSessionUpdated(SessionModel.fromMap(data));
        } else if (op == 'DELETE') {
          final id = oldData?['id'] as String?;
          if (id != null) _onSessionDeleted(id);
        }
      } catch (e) {
        debugPrint('[ForumSessionsCubit] Server broadcast callback error: $e');
      }
    };

    ForumBroadcastService().register(
      fId,
      _sessionBroadcastListener!,
      event: 'session_mutation',
    );
    ForumBroadcastService().register(
      fId,
      _sessionDbListener!,
      event: 'forum_session_change',
    );
  }

  void _onSessionInserted(SessionModel session) {
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
    ForumBroadcastService().sendBroadcast(
      activeForumId,
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
      final window = await _repo.getForumEventWindow(
        forumId: activeForumId.isNotEmpty ? activeForumId : null,
        forumReference: forumReference,
      );

      if (window.forumId != null) {
        _resolvedForumId = window.forumId;
        _resolvedForumCreatedAt = window.forumCreatedAt;
      }

      if (activeForumId.isEmpty) {
        throw Exception('Forum not found or reference is invalid.');
      }

      final sessions = await _repo.getSessions(activeForumId);

      emit(state.copyWith(
        sessions: sessions,
        isLoading: false,
        eventStartsAt: window.eventStartsAt,
        eventEndsAt: window.eventEndsAt,
      ));
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
      final savedSession =
          await _repo.addSession(session, activeForumId, activeForumCreatedAt);

      _onSessionInserted(savedSession);
      _broadcastMutation('insert', savedSession);

      emit(state.copyWith(isLoading: false));
    } catch (e) {
      emit(state.copyWith(
          isLoading: false, errorMessage: 'Failed to add session: $e'));
    }
  }

  Future<void> updateSession(SessionModel session) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final savedSession = await _repo.updateSession(
          session, activeForumId, activeForumCreatedAt);

      _onSessionUpdated(savedSession);
      _broadcastMutation('update', savedSession);

      emit(state.copyWith(isLoading: false));
    } catch (e) {
      emit(state.copyWith(
          isLoading: false, errorMessage: 'Failed to update session: $e'));
    }
  }

  /// Map of pending deletion timers keyed by session id.
  final Map<String, Timer> _pendingDeletionTimers = {};

  /// Tracks original sessions that are currently in the grace period of deletion.
  final Map<String, SessionModel> _stagedDeletedSessions = {};

  /// Deletes a session with a grace period for Undo.
  /// If [gracePeriod] is non-zero, the session is optimistically removed from the
  /// local state immediately, but the Supabase delete and realtime broadcast are
  /// deferred until the timer elapses. Calling [undoDeleteSession] restores it with 0 backend calls.
  void deleteSession(SessionModel session, {Duration gracePeriod = const Duration(seconds: 5)}) {
    _pendingDeletionTimers[session.id]?.cancel();

    _stagedDeletedSessions[session.id] = session;
    _onSessionDeleted(session.id);

    if (gracePeriod == Duration.zero) {
      _commitDeleteSession(session);
      return;
    }

    _pendingDeletionTimers[session.id] = Timer(gracePeriod, () {
      _pendingDeletionTimers.remove(session.id);
      _commitDeleteSession(session);
    });
  }

  /// Cancels a staged session deletion and restores it back into state.
  void undoDeleteSession(SessionModel session) {
    final timer = _pendingDeletionTimers.remove(session.id);
    final staged = _stagedDeletedSessions.remove(session.id) ?? session;
    if (timer != null) {
      timer.cancel();
      _onSessionInserted(staged);
    }
  }

  Future<void> _commitDeleteSession(SessionModel session) async {
    _stagedDeletedSessions.remove(session.id);
    try {
      await _repo.deleteSession(session.id);

      ForumBroadcastService().sendBroadcast(
        activeForumId,
        event: 'session_mutation',
        payload: {
          'action': 'delete',
          'session': {'id': session.id},
        },
      );
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(
            isLoading: false, errorMessage: 'Failed to delete session: $e'));
        // Re-insert into state if delete failed
        _onSessionInserted(session);
      }
    }
  }

  @override
  Future<void> close() {
    for (final timer in _pendingDeletionTimers.values) {
      timer.cancel();
    }
    _pendingDeletionTimers.clear();
    _stagedDeletedSessions.clear();
    if (_realtimeForumId != null) {
      if (_sessionBroadcastListener != null) {
        ForumBroadcastService().unregister(
          _realtimeForumId!,
          _sessionBroadcastListener!,
          event: 'session_mutation',
        );
      }
      if (_sessionDbListener != null) {
        ForumBroadcastService().unregister(
          _realtimeForumId!,
          _sessionDbListener!,
          event: 'forum_session_change',
        );
      }
    }
    return super.close();
  }
}
