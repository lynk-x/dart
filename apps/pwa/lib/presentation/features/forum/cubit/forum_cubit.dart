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
  final String forumReference;
  String? forumId;
  late String userId;
  late String userName;
  RealtimeChannel? _channel;
  RealtimeChannel? _statusChannel;
  RealtimeChannel? _forumStatusChannel;
  RealtimeChannel? get channel => _channel;
  Timer? _progressTimer;

  ForumCubit({
    required ForumRepository repo,
    required this.forumReference,
  })  : _repo = repo,
        super(const ForumState()) {
    final user =
        Supabase.instance.client.auth.currentUser; // keep — auth, not data
    userId = user?.id ?? kGuestUserId;
    userName = 'A User';
  }

  Future<void> init() async {
    await _loadCachedPermissions();
    await _syncUserStatus();
    final fId = forumId;
    if (fId != null) {
      await refreshMembers();
      _setupUserStatusListener();
      _setupForumStatusListener();
      _setupReactionListeners();
      _markAsRead();
    }
  }

  Future<void> _loadCachedPermissions() async {
    // Relying on real-time and fresh fetch for now since we are in PWA mode.
  }

  Future<void> refreshMembers() async {
    final fId = forumId;
    if (fId == null) return;
    try {
      final data = await _repo.getForumMembers(fId);

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
    final fId = forumId;
    if (userId == kGuestUserId || fId == null) return;
    _statusChannel?.unsubscribe();

    _statusChannel = _repo.subscribeToMemberChanges(fId, userId, (payload) {
      final data = payload.newRecord;
      if (data['forum_id'] == fId) {
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
    }).subscribe();
  }

  void _setupForumStatusListener() {
    final fId = forumId;
    if (fId == null) return;
    _forumStatusChannel?.unsubscribe();
    _forumStatusChannel = _repo.subscribeToForumChanges(fId, (payload) {
      final String? newStatus = payload.newRecord['status'] as String?;
      if (newStatus != null && !isClosed) {
        emit(state.copyWith(forumStatus: newStatus));
      }
    }).subscribe();
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
          .schema('api')
          .from('v1_profiles')
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
      DateTime? eventEndsAtFromDb;
      DateTime? forumCreatedAtFromDb;
      DateTime? channelCreatedAtFromDb;

      try {
        final result = await _repo.getForumWithMemberStatusByReference(
            forumReference, userId);
        final forumData = result['forum'] as Map<String, dynamic>?;
        final memberData = result['member'] as Map<String, dynamic>?;
        final channelData = result['channel'] as Map<String, dynamic>?;

        if (forumData != null) {
          forumId = forumData['id'] as String;
          _channel?.unsubscribe();
          _channel = Supabase.instance.client.channel(
              'forum_reactions_$forumId'); // keep — broadcast channel, not data

          forumStatus = forumData['status'] as String? ?? 'open';
          eventIdFromDb = forumData['event_id'] as String?;
          accountIdFromDb = forumData['account_id'] as String?;
          final eventCreatedAtRaw = forumData['event_created_at'];
          eventCreatedAtFromDb = eventCreatedAtRaw != null
              ? DateTime.parse(eventCreatedAtRaw as String)
              : null;
          final eventEndsAtRaw = forumData['event_ends_at'];
          eventEndsAtFromDb = eventEndsAtRaw != null
              ? DateTime.parse(eventEndsAtRaw as String)
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
          hasMutedLiveChatsMedia =
              memberData['has_muted_live_chats_media'] == true;
          final role = memberData['role_id'] as String?;
          isModerator = role == 'moderator' || role == 'organizer';
          isOrganizer = role == 'organizer';
        }
      } catch (e) {
        debugPrint('[ForumCubit] Forum/member sync error: $e');
      }

      if (!isClosed) {
        emit(state.copyWith(
          forumId: forumId,
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
          eventEndsAt: eventEndsAtFromDb,
          forumCreatedAt: forumCreatedAtFromDb,
          channelId: channelIdFromDb,
          channelCreatedAt: channelCreatedAtFromDb,
        ));

        if (forumId != null) {
          _syncForumProgress(forumId!, forumCreatedAtFromDb);
        }
      }
    } catch (e, stack) {
      debugPrint('[ForumCubit] Global sync error: $e\n$stack');
    }
  }

  Future<void> toggleMuteLiveChatsMedia(bool val) async {
    final fId = forumId;
    if (userId == kGuestUserId || fId == null) return;
    emit(state.copyWith(hasMutedLiveChatsMedia: val));
    try {
      await _repo.updateMemberSettings(
        fId,
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
    _forumStatusChannel?.unsubscribe();
    _progressTimer?.cancel();
    return super.close();
  }

  Future<void> _markAsRead() async {
    final fId = forumId;
    if (userId == kGuestUserId || fId == null) return;
    try {
      await _repo.markForumAsRead(fId);
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  void setTabIndex(int index) => emit(state.copyWith(currentTabIndex: index));

  // ── Moderation ─────────────────────────────────────────────────────────────

  /// Returns `true` on success, `false` if permission denied or RPC failed.
  Future<bool> muteUser(String targetUserId, {String? reason}) async {
    final fId = forumId;
    if (!state.isModerator || fId == null) return false;
    try {
      await _repo.moderateUser(
        targetUserId: targetUserId,
        action: 'mute',
        forumId: fId,
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
    final fId = forumId;
    if (!state.isOrganizer || fId == null) return false;
    try {
      await _repo.moderateUser(
        targetUserId: targetUserId,
        action: 'ban',
        forumId: fId,
        reason: reason ?? 'Banned by organizer',
      );
      return true;
    } catch (e, stack) {
      debugPrint('[ForumCubit] banUser error: $e\n$stack');
      return false;
    }
  }

  /// Returns `true` on success, `false` if permission denied or RPC failed.
  /// Only organizers may promote members to moderator — mirrors banUser's
  /// gate, and the backend independently enforces this via
  /// internal.fn_guard_forum_member_role (a BEFORE UPDATE trigger on
  /// social.forum_members) since this check alone is UI-only.
  Future<bool> makeModerator(String userIdToPromote) async {
    final fId = forumId;
    if (!state.isOrganizer || fId == null) return false;
    try {
      await _repo.updateMemberRole(fId, userIdToPromote, 'moderator');
      return true;
    } catch (e, stack) {
      debugPrint('[ForumCubit] makeModerator error: $e\n$stack');
      return false;
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

  /// Returns `true` on success, `false` if permission denied or RPC failed.
  /// The RPC (api.pin_message/unpin_message) independently checks
  /// can_manage_forum server-side — the isModerator gate below is a UI-only
  /// fast path, same convention as muteUser/banUser/makeModerator above.
  /// Previously this went through a raw client-side table UPDATE, which the
  /// base RLS policy silently limited to the message's own author, so a
  /// moderator pinning someone else's message affected 0 rows with no error
  /// surfaced at all — returning a bool here lets the caller show a
  /// snackbar on failure instead of that silent no-op.
  Future<bool> pinMessage(ChatMessage message) async {
    if (!state.isModerator) return false;
    try {
      if (message.isPinned) {
        await _repo.unpinMessage(message.id, message.createdAt);
      } else {
        await _repo.pinMessage(message.id, message.createdAt);
      }
      return true;
    } catch (e, stack) {
      debugPrint('[ForumCubit] pinMessage error: $e\n$stack');
      return false;
    }
  }

  Future<void> updateForumStatus(String status) async {
    final fId = forumId;
    if (!state.isOrganizer || fId == null) return;
    try {
      await _repo.updateForumStatus(fId, status);
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  Future<void> _syncForumProgress(
      String forumId, DateTime? forumCreatedAt) async {
    try {
      final sessions =
          await _repo.getForumSessions(forumId, forumCreatedAt: forumCreatedAt);

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
          // Event is over — stop the ticker to avoid unnecessary rebuilds.
          _progressTimer?.cancel();
          _progressTimer = null;
        } else {
          final totalDuration =
              lastSessionEnd.difference(firstSessionStart).inSeconds;
          final elapsed = now.difference(firstSessionStart).inSeconds;
          final progress = (totalDuration == 0)
              ? 1.0
              : (elapsed / totalDuration).clamp(0.0, 1.0);
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

  void handleEmojiTap(String emoji) {
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

    _channel?.subscribe();
  }
}
