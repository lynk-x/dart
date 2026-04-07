import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'forum_state.dart';
import 'package:flutter/foundation.dart';
import 'package:lynk_x/presentation/features/forum/services/forum_cache.dart';
import 'package:lynk_core/core.dart';

/// The core ForumCubit handling global state, permissions, members, and coordination.
class ForumCubit extends Cubit<ForumState> {
  final String forumId;
  late final String userId;
  late final String userName;
  RealtimeChannel? _channel;
  RealtimeChannel? _statusChannel;
  RealtimeChannel? get channel => _channel;
  Timer? _progressTimer;

  ForumCubit({this.forumId = '00000000-0000-0000-0000-000000000000'})
      : super(const ForumState()) {
    final user = Supabase.instance.client.auth.currentUser;
    userId = user?.id ?? kGuestUserId;
    userName = user?.userMetadata?['full_name'] ?? 'A User';
  }

  Future<void> init() async {
    _channel = Supabase.instance.client.channel('forum_$forumId');
    // We subscribe here so children cubits can use the same channel
    _channel?.subscribe();

    await _syncUserStatus();
    await _loadCachedPermissions();
    await refreshMembers();
    _setupUserStatusListener();
    _setupForumStatusListener();
    _setupReactionListeners();
    _markAsRead();
  }

  Future<void> _loadCachedPermissions() async {
    if (userId == kGuestUserId) return;
    try {
      final cached = await ForumCache.getCachedMemberInfo(forumId, userId);
      if (cached != null && !isClosed) {
        final role = cached['role'] as String?;

        emit(
          state.copyWith(
            isModerator: role == 'moderator' || role == 'organizer',
            isOrganizer: role == 'organizer',
            // Optionally map specific capabilities here if needed
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  Future<void> refreshMembers() async {
    try {
      final data = await Supabase.instance.client
          .from('forum_members')
          .select('user_profile(id, full_name, avatar_url, is_premium)')
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
    if (userId == kGuestUserId) return;
    try {
      final data = await Supabase.instance.client
          .from('user_profile')
          .select('is_premium')
          .eq('id', userId)
          .single();

      bool isPremium = data['is_premium'] == true;

      bool isMuted = false;
      bool hasMutedLiveChatsMedia = false;
      bool isModerator = false;
      bool isOrganizer = false;

      String forumStatus = 'active';
      String? eventIdFromDb;
      try {
        final forumData = await Supabase.instance.client
            .from('forums')
            .select('status, event_id')
            .eq('id', forumId)
            .maybeSingle();

        if (forumData != null) {
          forumStatus = forumData['status'] as String? ?? 'active';
          eventIdFromDb = forumData['event_id'] as String?;
        }
      } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }

      try {
        final memberData = await Supabase.instance.client
            .from('forum_members')
            .select(
              'is_muted, has_muted_live_chats_media, role_id, forum_roles(default_capabilities)',
            )
            .eq('forum_id', forumId)
            .eq('user_id', userId)
            .maybeSingle();

        if (memberData != null) {
          isMuted = memberData['is_muted'] == true;
          hasMutedLiveChatsMedia =
              memberData['has_muted_live_chats_media'] == true;
          final roleId = memberData['role_id'] as String?;
          final forumRoles = memberData['forum_roles'] as Map<String, dynamic>?;
          final capabilities =
              (forumRoles?['default_capabilities'] as Map<String, dynamic>?) ??
                  {};
          isModerator = roleId == 'moderator' || roleId == 'organizer';
          isOrganizer = roleId == 'organizer';

          // Cache the latest status for offline access
          await ForumCache.cacheMemberInfo(
            forumId: forumId,
            userId: userId,
            role: roleId ?? 'member',
            capabilities: capabilities,
          );
        }
      } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }

      if (!isClosed) {
        emit(
          state.copyWith(
            isPremium: isPremium,
            showAds: !isPremium, // Default to off for premium users
            isMuted: isMuted,
            hasMutedLiveChatsMedia: hasMutedLiveChatsMedia,
            isModerator: isModerator,
            isOrganizer: isOrganizer,
            forumStatus: forumStatus,
            eventId: eventIdFromDb,
          ),
        );

        if (eventIdFromDb != null) {
          _syncEventProgress(eventIdFromDb);
        }
      }
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  void toggleMuteLiveChatsMedia(bool val) async {
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

  Future<void> muteUser(String targetUserId, {String? reason}) async {
    if (!state.isModerator) return;
    try {
      await Supabase.instance.client.rpc('moderate_user_safe', params: {
        'p_target_user_id': targetUserId,
        'p_action': 'mute',
        'p_forum_id': forumId,
        'p_reason': reason ?? 'Violated forum rules',
      });
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
    }
  }

  Future<void> banUser(String targetUserId, {String? reason}) async {
    if (!state.isOrganizer) return;
    try {
      await Supabase.instance.client.rpc('moderate_user_safe', params: {
        'p_target_user_id': targetUserId,
        'p_action': 'ban',
        'p_reason': reason ?? 'Banned by organizer',
      });
    } catch (e, stack) {
      debugPrint('[ForumCubit] Error: $e\n$stack');
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
          .from('forum_messages')
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

  void handleEmojiTap(String emoji, {ChatMessage? message}) {
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

    // 3. Handle Message Reaction (Slack-style) if a message is targetted
    if (message != null) {
      _persistReaction(message, emoji);
    }
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
      await Supabase.instance.client.from('message_reactions').upsert({
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
