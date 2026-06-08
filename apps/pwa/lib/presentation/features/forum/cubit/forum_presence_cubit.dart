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

    // Register the sync callback BEFORE tracking so the initial sync is caught.
    channel?.onPresenceSync((_) {
      if (!isClosed) _updatePresenceFromChannel();
    });

    channel?.onPresenceJoin((_) {
      if (!isClosed) _updatePresenceFromChannel();
    });

    channel?.onPresenceLeave((_) {
      if (!isClosed) _updatePresenceFromChannel();
    });

    await _trackUser();

    _updatePresenceFromChannel();
  }

  void _updatePresenceFromChannel() {
    final presenceStates = channel?.presenceState();
    if (presenceStates == null) {
      debugPrint('[ForumPresenceCubit] presenceState() returned null');
      return;
    }

    debugPrint('[ForumPresenceCubit] presenceState() type: ${presenceStates.runtimeType}, length: ${presenceStates.length}');

    final List<Map<String, dynamic>> users = [];
    final Set<String> uniqueUserIds = {};

    for (final presence in presenceStates) {
      final presences = presence.presences;
      debugPrint('[ForumPresenceCubit] presences type: ${presences.runtimeType}, length: ${presences.length}');
      for (final p in presences) {
        final data = Map<String, dynamic>.from(p.payload);
        final uid = data['user_id'] as String? ?? data['id'] as String?;
        if (data['user_name'] == null && data['full_name'] != null) {
          data['user_name'] = data['full_name'];
        }

        if (uid != null && !uniqueUserIds.contains(uid)) {
          uniqueUserIds.add(uid);
          users.add(data);
        }
      }
    }

    if (state.isTracking && !uniqueUserIds.contains(userId)) {
      final me = <String, dynamic>{
        'user_id': userId,
        'id': userId,
        'user_name': userName,
        'full_name': userName,
        'is_organizer': isOrganizer,
        'is_premium': isPremium,
        'status': 'Online',
      };
      uniqueUserIds.add(userId);
      users.add(me);
      debugPrint('[ForumPresenceCubit] Added current user to list (server sync delayed)');
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
