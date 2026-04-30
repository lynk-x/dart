import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'forum_state.dart';
import 'package:flutter/foundation.dart';
import 'package:lynk_core/core.dart';

/// The core ForumCubit handling global state, permissions, members, and coordination.
class ForumCubit extends Cubit<ForumState> {
  final String forumId;
  late String userId;
  late String userName;
  RealtimeChannel? _channel;
  RealtimeChannel? _statusChannel;
  RealtimeChannel? get channel => _channel;
  Timer? _progressTimer;

  ForumCubit({this.forumId = '00000000-0000-0000-0000-000000000000'})
      : super(const ForumState()) {
    final user = Supabase.instance.client.auth.currentUser;
    userId = user?.id ?? kGuestUserId;
    final initialName = user?.userMetadata?['full_name'] ?? 'A User';
    userName = initialName;
    _channel = Supabase.instance.client.channel('forum_$forumId');
    _channel?.subscribe();
    emit(state.copyWith(userName: initialName));
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
      final data = await Supabase.instance.client
          .from('forum_members')
          .select('user_profile(id, user_name, avatar_url, is_premium)')
          .eq('forum_id', forumId);

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

    _statusChannel = Supabase.instance.client
        .channel('user_status_$forumId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'forum_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
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
          },
        )
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
      final data = await Supabase.instance.client
          .from('user_profile')
          .select('user_name, is_premium')
          .eq('id', userId)
          .single();

      final handle = data['user_name'] as String? ?? 'A User';
      final isPremium = data['is_premium'] == true;
      userName = handle;

      bool isMuted = false;
      bool hasMutedLiveChatsMedia = false;
      bool isModerator = false;
      bool isOrganizer = false;

      String forumStatus = 'open';
      String forumName = 'Community Forum';
      String? eventIdFromDb;

      // 1. Fetch Forum Info
      try {
        final forumData = await Supabase.instance.client
            .from('forums')
            .select('status, event_id, events(title)')
            .eq('id', forumId)
            .maybeSingle();

        if (forumData != null) {
          forumStatus = forumData['status'] as String? ?? 'open';
          eventIdFromDb = forumData['event_id'] as String?;
          forumName = forumData['title'] as String? ?? 
                      forumData['events']?['title'] as String? ?? 
                      'Community Forum';
        }
      } catch (e) {
        debugPrint('[ForumCubit] Forum fetch error: $e');
      }

      // 2. Fetch specific member role and mutes
      try {
        final memberData = await Supabase.instance.client
            .from('forum_members')
            .select('is_muted, has_muted_live_chats_media, role_id')
            .eq('forum_id', forumId)
            .eq('user_id', userId)
            .maybeSingle();

        if (memberData != null) {
          isMuted = memberData['is_muted'] == true;
          hasMutedLiveChatsMedia = memberData['has_muted_live_chats_media'] == true;
          final role = memberData['role_id'] as String?;
          isModerator = role == 'moderator' || role == 'organizer';
          isOrganizer = role == 'organizer';
        }
      } catch (e) {
        debugPrint('[ForumCubit] Member sync error: $e');
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
        ));

        if (eventIdFromDb != null) {
          _syncEventProgress(eventIdFromDb);
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
      await Supabase.instance.client
          .from('forum_members')
          .update({'has_muted_live_chats_media': val})
          .eq('forum_id', forumId)
          .eq('user_id', userId);
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
      await Supabase.instance.client.rpc('mark_forum_as_read', params: {
        'p_forum_id': forumId,
      });
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
      await Supabase.instance.client.rpc('moderate_user_safe', params: {
        'p_target_user_id': targetUserId,
        'p_action': 'mute',
        'p_forum_id': forumId,
        'p_reason': reason ?? 'Violated forum rules',
      });
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
      await Supabase.instance.client.rpc('moderate_user_safe', params: {
        'p_target_user_id': targetUserId,
        'p_action': 'ban',
        'p_reason': reason ?? 'Banned by organizer',
      });
      return true;
    } catch (e, stack) {
      debugPrint('[ForumCubit] banUser error: $e\n$stack');
      return false;
    }
  }

  Future<void> makeModerator(String userIdToPromote) async {
    try {
      await Supabase.instance.client
          .from('forum_members')
          .update({'role_id': 'moderator'})
          .eq('forum_id', forumId)
          .eq('user_id', userIdToPromote);
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  Future<void> reportUser(String targetUserId, String reason,
      {String? messageId}) async {
    try {
      await Supabase.instance.client.rpc('submit_report', params: {
        'p_target_user_id': targetUserId,
        'p_target_message_id': messageId,
        'p_reason_id': 'general_abuse', // Standard reasoning
        'p_description': reason,
      });
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
      await Supabase.instance.client
          .schema('forum_messages').from('forum_messages')
          .update({'is_pinned': true}).eq('id', message.id);
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }


  Future<void> updateForumStatus(String status) async {
    if (!state.isOrganizer) return;
    try {
      await Supabase.instance.client
          .from('forums')
          .update({'status': status})
          .eq('id', forumId);
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  Future<void> _syncEventProgress(String eventId) async {
    try {
      final sessions = await Supabase.instance.client
          .from('event_sessions')
          .select('starts_at, ends_at')
          .eq('event_id', eventId)
          .order('starts_at', ascending: true);

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
      // Toggle reaction (if already exist delete, else insert)
      // For now simple insert-or-ignore/upsert via RPC or logic
      // Assuming a simple insert for demo, but in production we'd use a toggle RPC
      await Supabase.instance.client.schema('message_reactions').from('message_reactions').upsert({
        'message_id': message.id,
        'message_created_at': message.createdAt.toIso8601String(),
        'user_id': userId,
        'emoji_code': emoji,
      });

      // Broadcast reaction update so others can update their count immediately
      _channel?.sendBroadcastMessage(
        event: 'message_reaction',
        payload: {
          'message_id': message.id,
          'emoji_code': emoji,
          'user_id': userId,
          'action': 'added',
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
