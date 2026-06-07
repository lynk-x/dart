import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'forum_presence_state.dart';

class ForumPresenceCubit extends Cubit<ForumPresenceState> {
  final String forumId;
  final String userId;
  String userName;
  final bool isOrganizer;
  final bool isPremium;
  final RealtimeChannel? channel;

  ForumPresenceCubit({
    required this.forumId,
    required this.userId,
    required this.userName,
    required this.isOrganizer,
    required this.isPremium,
    this.channel,
  }) : super(const ForumPresenceState());

  void updateUserName(String newName) {
    if (userName != newName) {
      userName = newName;
      _trackUser();
    }
  }

  Future<void> init() async {
    await _setupPresenceListeners();
  }

  Future<void> _setupPresenceListeners() async {
    debugPrint('[ForumPresenceCubit] Setting up presence listeners for $forumId');

    channel?.onPresenceSync((payload) {
      debugPrint('[ForumPresenceCubit] Presence sync received');
      _updatePresence();
    });

    channel?.onPresenceJoin((payload) {
      debugPrint('[ForumPresenceCubit] User joined');
      _updatePresence();
    });

    channel?.onPresenceLeave((payload) {
      debugPrint('[ForumPresenceCubit] User left');
      _updatePresence();
    });

    await _trackUser();
    _updatePresence();

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!isClosed) _updatePresence();
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (!isClosed) _updatePresence();
    });
  }

  void _updatePresence() {
    final presenceStates = channel?.presenceState();
    if (presenceStates == null) return;

    final List<Map<String, dynamic>> users = [];
    final Set<String> uniqueUserIds = {};

    for (final presence in presenceStates) {
      for (final p in presence.presences) {
        final data = Map<String, dynamic>.from(p.payload);
        final uid = data['user_id'] as String? ?? data['id'] as String?;
        // Support both naming conventions for robustness during migration
        if (data['user_name'] == null && data['full_name'] != null) {
          data['user_name'] = data['full_name'];
        }
        
        if (uid != null && !uniqueUserIds.contains(uid)) {
          uniqueUserIds.add(uid);
          users.add(data);
        }
      }
    }

    debugPrint('[ForumPresenceCubit] Sync complete. Online users: ${users.length}');
    if (!isClosed) emit(state.copyWith(onlineUsers: users));
  }

  Future<void> _trackUser() async {
    debugPrint('[ForumPresenceCubit] Tracking user: $userId ($userName)');
    try {
      await channel?.track({
        'user_id': userId,
        'id': userId, // Fallback for components expecting 'id'
        'user_name': userName,
        'full_name': userName, // Fallback for older clients
        'is_organizer': isOrganizer,
        'is_premium': isPremium,
        'status': 'Online',
      });
      if (!isClosed) emit(state.copyWith(isTracking: true));
    } catch (e, stack) {
      debugPrint('[ForumPresenceCubit] Error in _trackUser: $e\n$stack');
    }
  }

  Future<void> untrackUser() async {
    try {
      await channel?.untrack();
      if (!isClosed) emit(state.copyWith(isTracking: false));
    } catch (e, stack) {
      debugPrint('[ForumPresenceCubit] Error in untrackUser: $e\n$stack');
    }
  }

  @override
  Future<void> close() {
    untrackUser();
    return super.close();
  }
}
