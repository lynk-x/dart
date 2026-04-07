import 'package:lynk_core/core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'forum_presence_state.dart';

class ForumPresenceCubit extends Cubit<ForumPresenceState> {
  final String forumId;
  final String userId;
  final String userName;
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

  void init() {
    _setupPresenceListeners();
  }

  void _setupPresenceListeners() {
    channel?.onPresenceSync((payload) {
      final presenceStates = channel?.presenceState();
      if (presenceStates != null) {
        final List<Map<String, dynamic>> users = [];
        final Set<String> uniqueUserIds = {};

        for (final presence in presenceStates) {
          for (final p in presence.presences) {
            final data = Map<String, dynamic>.from(p.payload);
            final uid = data['user_id'] as String?;
            if (uid != null && !uniqueUserIds.contains(uid)) {
              uniqueUserIds.add(uid);
              users.add(data);
            }
          }
        }
        if (!isClosed) emit(state.copyWith(onlineUsers: users));
      }
    });

    // Start tracking if already subscribed, otherwise we might need to wait for subscription status
    // But usually channel is provided already.
    _trackUser();
  }

  Future<void> _trackUser() async {
    if (userId == kGuestUserId) return;

    try {
      await channel?.track({
        'user_id': userId,
        'user_name': userName,
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
}
