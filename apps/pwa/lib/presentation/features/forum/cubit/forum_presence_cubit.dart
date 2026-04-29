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
    debugPrint('[ForumPresenceCubit] Setting up presence listeners for $forumId');
    
    channel?.onPresenceSync((payload) {
      debugPrint('[ForumPresenceCubit] Presence sync received');
      _updatePresence();
    });

    // Subscribe to status changes. 
    // Note: If the channel was already subscribed by ForumCubit, this callback 
    // will still fire with 'subscribed' in the latest Supabase SDK versions.
    channel?.subscribe((status, error) {
      debugPrint('[ForumPresenceCubit] Channel status: $status, error: $error');
      if (status == RealtimeSubscribeStatus.subscribed) {
        _trackUser();
      }
    });

    // In case it's already subscribed and we missed the callback transition, 
    // we attempt an immediate track if the feature flag allowed us to reach here.
    // Supabase will ignore duplicate tracks if already tracking the same payload.
    _trackUser();
    _updatePresence();
  }

  void _updatePresence() {
    final presenceStates = channel?.presenceState();
    if (presenceStates == null) return;

    final List<Map<String, dynamic>> users = [];
    final Set<String> uniqueUserIds = {};

    for (final presence in presenceStates) {
      for (final p in presence.presences) {
        final data = Map<String, dynamic>.from(p.payload);
        final uid = data['user_id'] as String?;
        // If it's a guest, we might want to show them anyway, but for now 
        // we'll keep the deduplication by user_id. 
        // If multiple guests have the same ID, they show up as one entry.
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

  @override
  Future<void> close() {
    untrackUser();
    return super.close();
  }
}
