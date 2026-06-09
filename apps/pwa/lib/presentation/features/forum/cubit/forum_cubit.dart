import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/data/repositories/repositories.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'forum_state.dart';
import 'package:flutter/foundation.dart';
import 'package:lynk_core/core.dart';

/// The core ForumCubit handling global state, permissions, members, and coordination.
class ForumCubit extends Cubit<ForumState> {
  final ForumRepository _repo;
  final String forumId;
  late String userId;
  late String userName;
  RealtimeChannel? _channel;
  RealtimeChannel? _statusChannel;
  RealtimeChannel? get channel => _channel;
  Timer? _progressTimer;

  ForumCubit({
    required ForumRepository repo,
    this.forumId = '00000000-0000-0000-0000-000000000000',
  })  : _repo = repo,
        super(const ForumState()) {
    final user = Supabase.instance.client.auth.currentUser; // keep — auth, not data
    userId = user?.id ?? kGuestUserId;
    userName = 'A User';
    _channel = Supabase.instance.client.channel('forum_$forumId'); // keep — broadcast channel, not data
    _channel?.subscribe();
    // userName is intentionally not emitted here — _syncUserStatus sets it
    // from user_profile.user_name which is the canonical display name.
  }

  Future<void> init() async {
    await _loadCachedPermissions();
    await _syncUserStatus();
    await refreshMembers();
    _setupUserStatusListener();
    _setupForumStatusListener();
    _setupReactionListeners();
    _markAsRead();
  }

  Future<void> _loadCachedPermissions() async {
    // Relying on real-time and fresh fetch for now since we are in PWA mode.
  }

  Future<void> refreshMembers() async {
    try {
      final data = await _repo.getForumMembers(forumId);

      final members = data
          .map((json) => json['user_profile'] as Map<String, dynamic>?)
          .where((m) => m != null)
          .map((m) => m!)
          .toList();

      if (!isClosed) {
        emit(state.copyWith(members: members));
      }
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  void _setupUserStatusListener() {
    if (userId == kGuestUserId) return;

    _statusChannel = _repo.subscribeToMemberChanges(forumId, userId, (payload) {
          final data = payload.newRecord;
          if (data['forum_id'] == forumId) {
            final String? roleId = data['role_id'] as String?;
            final bool isMuted = data['is_muted'] == true;
            final bool hasMutedLiveChatsMedia =
                data['has_muted_live_chats_media'] == true;

            if (!isClosed) {
              emit(state.copyWith(
                isMuted: isMuted,
                hasMutedLiveChatsMedia: hasMutedLiveChatsMedia,
                isModerator: roleId == 'moderator' || roleId == 'organizer',
                isOrganizer: roleId == 'organizer',
              ));
            }
          }
        })
        .subscribe();
  }

  void _setupForumStatusListener() {
    _channel?.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'forums',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: forumId,
      ),
      callback: (payload) {
        final String? newStatus = payload.newRecord['status'] as String?;
        if (newStatus != null && !isClosed) {
          emit(state.copyWith(forumStatus: newStatus));
        }
      },
    );
  }

  Future<void> _syncUserStatus() async {
    if (userId == kGuestUserId) {
      userName = 'Guest';
      return;
    }
    try {
      String handle = 'User';
      bool isPremium = true;

      final data = await Supabase.instance.client
          .from('user_profile')
          .select('user_name, is_premium')
          .eq('id', userId)
          .single();

      handle = data['user_name'] as String? ?? 'A User';
      isPremium = data['is_premium'] == true;
      userName = handle;

      bool isMuted = false;
      bool hasMutedLiveChatsMedia = false;
      bool isModerator = false;
      bool isOrganizer = false;

      String forumStatus = 'open';
      String forumName = 'Community Forum';
      String? eventIdFromDb;
      String? accountIdFromDb;
      String? channelIdFromDb;

      DateTime? eventCreatedAtFromDb;
      DateTime? forumCreatedAtFromDb;
      DateTime? channelCreatedAtFromDb;

      try {
        final result = await _repo.getForumWithMemberStatus(forumId, userId);
        final forumData = result['forum'] as Map<String, dynamic>?;
        final memberData = result['member'] as Map<String, dynamic>?;
        final channelData = result['channel'] as Map<String, dynamic>?;

        if (forumData != null) {
          forumStatus = forumData['status'] as String? ?? 'open';
          eventIdFromDb = forumData['event_id'] as String?;
          accountIdFromDb = forumData['account_id'] as String?;
          final eventCreatedAtRaw = forumData['event_created_at'];
          eventCreatedAtFromDb = eventCreatedAtRaw != null
              ? DateTime.parse(eventCreatedAtRaw as String)
              : null;
          final forumCreatedAtRaw = forumData['created_at'];
          forumCreatedAtFromDb = forumCreatedAtRaw != null
              ? DateTime.parse(forumCreatedAtRaw as String)
              : null;
          forumName = forumData['event_title'] as String? ?? 'Community Forum';
        }

        if (channelData != null) {
          channelIdFromDb = channelData['id'] as String?;
          final channelCreatedAtRaw = channelData['created_at'];
          channelCreatedAtFromDb = channelCreatedAtRaw != null
              ? DateTime.parse(channelCreatedAtRaw as String)
              : null;
        }

        if (memberData != null) {
          isMuted = memberData['is_muted'] == true;
          hasMutedLiveChatsMedia = memberData['has_muted_live_chats_media'] == true;
          final role = memberData['role_id'] as String?;
          isModerator = role == 'moderator' || role == 'organizer';
          isOrganizer = role == 'organizer';
        }
      } catch (e) {
        debugPrint('[ForumCubit] Forum/member sync error: $e');
      }

      if (!isClosed) {
        emit(state.copyWith(
          userName: handle,
          isPremium: isPremium,
          showAds: !isPremium,
          isMuted: isMuted,
          hasMutedLiveChatsMedia: hasMutedLiveChatsMedia,
          isModerator: isModerator,
          isOrganizer: isOrganizer,
          forumStatus: forumStatus,
          forumName: forumName,
          eventId: eventIdFromDb,
          accountId: accountIdFromDb,
          eventCreatedAt: eventCreatedAtFromDb,
          forumCreatedAt: forumCreatedAtFromDb,
          channelId: channelIdFromDb,
          channelCreatedAt: channelCreatedAtFromDb,
        ));

        if (eventIdFromDb != null) {
          _syncEventProgress(eventIdFromDb, eventCreatedAtFromDb);
        }
      }
    } catch (e, stack) {
      debugPrint('[ForumCubit] Global sync error: $e\n$stack');
    }
  }

  Future<void> toggleMuteLiveChatsMedia(bool val) async {
    if (userId == kGuestUserId) return;
    emit(state.copyWith(hasMutedLiveChatsMedia: val));
    try {
      await _repo.updateMemberSettings(
        forumId,
        userId,
        {'has_muted_live_chats_media': val},
      );
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  void toggleAds(bool enabled) {
    if (state.isPremium && !isClosed) {
      emit(state.copyWith(showAds: enabled));
    }
  }

  @override
  Future<void> close() {
    _channel?.unsubscribe();
    _statusChannel?.unsubscribe();
    _progressTimer?.cancel();
    return super.close();
  }

  Future<void> _markAsRead() async {
    if (userId == kGuestUserId) return;
    try {
      await _repo.markForumAsRead(forumId);
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  void setTabIndex(int index) => emit(state.copyWith(currentTabIndex: index));

  // ── Moderation ─────────────────────────────────────────────────────────────

  /// Returns `true` on success, `false` if permission denied or RPC failed.
  Future<bool> muteUser(String targetUserId, {String? reason}) async {
    if (!state.isModerator) return false;
    try {
      await _repo.moderateUser(
        targetUserId: targetUserId,
        action: 'mute',
        forumId: forumId,
        reason: reason,
      );
      return true;
    } catch (e, stack) {
      debugPrint('[ForumCubit] muteUser error: $e\n$stack');
      return false;
    }
  }

  /// Returns `true` on success, `false` if permission denied or RPC failed.
  Future<bool> banUser(String targetUserId, {String? reason}) async {
    if (!state.isOrganizer) return false;
    try {
      await _repo.moderateUser(
        targetUserId: targetUserId,
        action: 'ban',
        forumId: forumId,
        reason: reason ?? 'Banned by organizer',
      );
      return true;
    } catch (e, stack) {
      debugPrint('[ForumCubit] banUser error: $e\n$stack');
      return false;
    }
  }

  Future<void> makeModerator(String userIdToPromote) async {
    try {
      await _repo.updateMemberRole(forumId, userIdToPromote, 'moderator');
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  Future<void> reportUser(String targetUserId, String reason,
      {String? messageId}) async {
    try {
      await _repo.submitReport(
        targetUserId: targetUserId,
        messageId: messageId,
        reasonId: 'general_abuse', // Standard reasoning
        description: reason,
      );
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  void setMentionedMedia(ForumMedia? media) {
    if (media == null) {
      emit(state.copyWith(clearMentionedMedia: true));
    } else {
      emit(state.copyWith(mentionedMedia: media));
    }
  }

  Future<void> pinMessage(ChatMessage message) async {
    if (!state.isModerator) return;
    try {
      await _repo.pinMessage(message.id);
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  Future<void> updateForumStatus(String status) async {
    if (!state.isOrganizer) return;
    try {
      await _repo.updateForumStatus(forumId, status);
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  Future<void> _syncEventProgress(String eventId, DateTime? eventCreatedAt) async {
    try {
      final sessions = await _repo.getEventSessions(eventId, eventCreatedAt: eventCreatedAt);

      if (sessions.isEmpty) return;

      void updateProgress() {
        if (isClosed) return;

        final now = DateTime.now();
        final firstSessionStart =
            DateTime.parse(sessions.first['starts_at'] as String);
        final lastSessionEnd =
            DateTime.parse(sessions.last['ends_at'] as String);

        if (now.isBefore(firstSessionStart)) {
          emit(state.copyWith(eventProgress: 0.0));
        } else if (now.isAfter(lastSessionEnd)) {
          emit(state.copyWith(eventProgress: 1.0));
        } else {
          final totalDuration =
              lastSessionEnd.difference(firstSessionStart).inSeconds;
          final elapsed = now.difference(firstSessionStart).inSeconds;
          final progress =
              (totalDuration == 0) ? 1.0 : (elapsed / totalDuration).clamp(0.0, 1.0);
          if (!isClosed) emit(state.copyWith(eventProgress: progress));
        }
      }

      updateProgress();
      _progressTimer?.cancel();
      _progressTimer =
          Timer.periodic(const Duration(minutes: 1), (_) => updateProgress());
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  void reactToMessage(ChatMessage message, String emoji) {
    // 1. Update local UI (Flying emoji)
    if (!isClosed) {
      emit(state.copyWith(
        selectedEmoji: emoji,
        emojiTrigger: state.emojiTrigger + 1,
      ));
    }

    // 2. Broadcast for others to see flying emoji
    _channel?.sendBroadcastMessage(
      event: 'live_reaction',
      payload: {'emoji': emoji},
    );

    // 3. Handle Message Reaction (Slack-style)
    _persistReaction(message, emoji);
  }

  void handleEmojiTap(String emoji) {
    // Legacy support for flying emojis only
    if (!isClosed) {
      emit(state.copyWith(
        selectedEmoji: emoji,
        emojiTrigger: state.emojiTrigger + 1,
      ));
    }
    _channel?.sendBroadcastMessage(
      event: 'live_reaction',
      payload: {'emoji': emoji},
    );
  }

  void waveAtUser(String targetUserId, String myUserName) {
    _channel?.sendBroadcastMessage(
      event: 'social_action',
      payload: {
        'action': 'wave',
        'from_name': myUserName,
        'from_user_id': userId,
        'to_user_id': targetUserId,
      },
    );
  }

  Future<void> _persistReaction(ChatMessage message, String emoji) async {
    if (userId == kGuestUserId) return;
    try {
      await _repo.toggleReaction(
        message.id,
        message.createdAt.toIso8601String(),
        userId,
        emoji,
      );

      _channel?.sendBroadcastMessage(
        event: 'message_reaction',
        payload: {
          'message_id': message.id,
          'emoji_code': emoji,
          'user_id': userId,
          'action': 'toggled',
        },
      );
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  void _setupReactionListeners() {
    _channel?.onBroadcast(
      event: 'live_reaction',
      callback: (payload) {
        final emoji = payload['emoji'] as String?;
        if (emoji != null && !isClosed) {
          emit(state.copyWith(
            selectedEmoji: emoji,
            emojiTrigger: state.emojiTrigger + 1,
          ));
        }
      },
    );

    _channel?.onBroadcast(
      event: 'message_reaction',
      callback: (payload) {
        // This can be used by Chat/Update cubits to update specific message counts locally
        // We'll handle this in the respective cubits via children communication or shared streams
      },
    );

    _channel?.onBroadcast(
      event: 'social_action',
      callback: (payload) {
        if (payload['action'] == 'wave' && payload['to_user_id'] == userId) {
          if (!isClosed) {
            emit(state.copyWith(
              waveFromName: payload['from_name'] as String?,
              waveFromUserId: payload['from_user_id'] as String?,
              waveTrigger: state.waveTrigger + 1,
            ));
          }
        }
      },
    );
  }
}
