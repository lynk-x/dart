import 'package:lynk_core/core.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/services/forum_cache.dart';
import 'forum_updates_state.dart';

class ForumUpdatesCubit extends Cubit<ForumUpdatesState> {
  static const _uuid = Uuid();
  final String forumId;
  final String userId;
  final String userName;
  final RealtimeChannel? channel;
  Timer? _searchTimer;

  ForumUpdatesCubit({
    required this.forumId,
    required this.userId,
    required this.userName,
    this.channel,
  }) : super(const ForumUpdatesState());

  Future<void> init() async {
    final cached = await ForumCache.getCachedMessages(forumId, userId,
        type: 'announcement');
    if (!isClosed) {
      emit(state.copyWith(messages: cached));
    }
    await refresh();
    _setupListeners();
  }

  void _setupListeners() {
    channel?.onBroadcast(
      event: 'new_message',
      callback: (payload) {
        if (payload.isEmpty) return;
        final msg = ChatMessage.fromMap(payload, userId);
        if (msg.type == MessageType.announcement) {
          onBroadcastMessageReceived(msg);
        }
      },
    );

    channel?.onBroadcast(
      event: 'message_reaction',
      callback: (payload) {
        final String? msgId = payload['message_id'] as String?;
        final String? emoji = payload['emoji_code'] as String?;
        final String? action = payload['action'] as String?;

        if (msgId == null || emoji == null) return;

        final index = state.messages.indexWhere((m) => m.id == msgId);
        if (index != -1) {
          final msg = state.messages[index];
          final updatedReactions = Map<String, int>.from(msg.reactions);
          if (action == 'added') {
            updatedReactions[emoji] = (updatedReactions[emoji] ?? 0) + 1;
          } else {
            updatedReactions[emoji] = (updatedReactions[emoji] ?? 1) - 1;
            if (updatedReactions[emoji]! <= 0) updatedReactions.remove(emoji);
          }

          _updateMessageInPlace(msgId, reactions: updatedReactions);
        }
      },
    );

    // Sync updates/deletes (e.g., pinning, soft-deletion)
    channel?.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'forum_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'forum_id',
        value: forumId,
      ),
      callback: (payload) {
        if (payload.eventType == PostgresChangeEvent.delete) {
          final id = payload.oldRecord['id'] as String?;
          final updated = state.messages.where((m) => m.id != id).toList();
          if (!isClosed) emit(state.copyWith(messages: updated));
        } else if (payload.eventType == PostgresChangeEvent.update) {
          final data = payload.newRecord;
          if (data['message_type'] != 'announcement') return;

          if (data['deleted_at'] != null) {
            final id = data['id'] as String?;
            final updated = state.messages.where((m) => m.id != id).toList();
            if (!isClosed) emit(state.copyWith(messages: updated));
          } else {
            _updateMessageInPlace(
              data['id'] as String,
              content: data['content'] as String?,
              isPinned: data['is_pinned'] == true,
            );
          }
        }
      },
    );

    // Re-sync on reconnection to catch missed broadcast/db messages
    channel?.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        refresh();
      }
    });
  }

  void onBroadcastMessageReceived(ChatMessage msg) {
    if (msg.userId == userId) return;
    if (state.messages.any((m) => m.id == msg.id)) return;
    emit(state.copyWith(messages: [msg, ...state.messages]));
  }

  Future<void> refresh() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true));
    try {
      var query = Supabase.instance.client
          .from('forum_messages')
          .select(
              '*, user_profile(full_name, is_premium), forum_members!inner(role_id), vw_message_reaction_counts(*)')
          .eq('forum_id', forumId)
          .eq('message_type', 'announcement');

      if (state.selectedCategory != null) {
        query = query.eq('hashtag', state.selectedCategory as Object);
      }

      if (state.searchQuery.isNotEmpty) {
        query = query.textSearch('fts', state.searchQuery, config: 'english');
      }

      final data = await query
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(20);
      final messages =
          data.map((json) => ChatMessage.fromMap(json, userId)).toList();
      await ForumCache.cacheMessages(messages, forumId);

      if (!isClosed) {
        emit(state.copyWith(messages: messages, isLoading: false));
      }
    } catch (e, stack) {
      debugPrint('[ForumUpdatesCubit] Error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || isClosed) return;
    emit(state.copyWith(isLoading: true));
    final startIndex = state.messages.length;
    try {
      var query = Supabase.instance.client
          .from('forum_messages')
          .select(
              '*, user_profile(full_name, is_premium), forum_members!inner(role_id), vw_message_reaction_counts(*)')
          .eq('forum_id', forumId)
          .eq('message_type', 'announcement');

      if (state.selectedCategory != null) {
        query = query.eq('hashtag', state.selectedCategory as Object);
      }

      if (state.searchQuery.isNotEmpty) {
        query = query.textSearch('fts', state.searchQuery, config: 'english');
      }

      final data = await query
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .range(startIndex, startIndex + 15);

      final more =
          data.map((json) => ChatMessage.fromMap(json, userId)).toList();
      await ForumCache.cacheMessages(more, forumId);

      if (!isClosed) {
        emit(state.copyWith(
          messages: [...state.messages, ...more],
          isLoading: false,
        ));
      }
    } catch (e, stack) {
      debugPrint('[ForumUpdatesCubit] Error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(isLoading: false));
    }
  }

  void setSearchQuery(String query) {
    emit(state.copyWith(searchQuery: query));
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      refresh();
    });
  }

  void sendMessage(String text, {required bool isOrganizer, required bool isPremium}) async {
    final messageId = _uuid.v4();
    final now = DateTime.now();
    final mediaId = state.mentionedMedia?.id;
    final imageUrl = state.mentionedMedia?.url;
    final category = _extractCategory(text) ?? state.selectedCategory;

    final newMessage = ChatMessage(
      id: messageId,
      sender: 'Me',
      userId: userId,
      message: text,
      createdAt: now,
      isMe: true,
      type: MessageType.announcement,
      imageUrl: imageUrl,
      thumbnailUrl: state.mentionedMedia?.thumbnailUrl,
      category: category,
      isSending: true,
    );

    emit(state.copyWith(
      messages: [newMessage, ...state.messages],
      clearMentionedMedia: true,
    ));

    if (userId != kGuestUserId) {
      try {
        await Supabase.instance.client.from('forum_messages').insert({
          'id': messageId,
          'forum_id': forumId,
          'author_id': userId,
          'content': text,
          'message_type': 'announcement',
          'hashtag': category,
          if (mediaId != null) 'media_id': mediaId,
        });

        _completeMessage(messageId);

        channel?.sendBroadcastMessage(
          event: 'new_message',
          payload: {
            'id': messageId,
            'author_id': userId,
            'content': text,
            'message_type': 'announcement',
            'created_at': now.toIso8601String(),
            'hashtag': category,
            if (mediaId != null) 'media_id': mediaId,
            if (imageUrl != null)
              'forum_media': {
                'url': imageUrl,
                'thumbnail_url': newMessage.thumbnailUrl,
              },
            'user_profile': {
              'full_name': userName,
              'is_premium': isPremium,
            },
            'forum_members': {'role_id': isOrganizer ? 'organizer' : 'member'}
          },
        );
      } catch (e, stack) {
      debugPrint('[ForumUpdatesCubit] Error: $e\n$stack');
        _failMessage(messageId);
      }
    }
  }

  void _completeMessage(String id) {
    _updateMessageInPlace(id, isSending: false, hasError: false);
  }

  void _failMessage(String id) {
    _updateMessageInPlace(id, isSending: false, hasError: true);
  }

  void _updateMessageInPlace(
    String id, {
    String? content,
    bool? isPinned,
    bool? isSending,
    bool? hasError,
    Map<String, int>? reactions,
  }) {
    final index = state.messages.indexWhere((m) => m.id == id);
    if (index == -1) return;

    final msg = state.messages[index];
    final updatedMsg = ChatMessage(
      id: msg.id,
      sender: msg.sender,
      userId: msg.userId,
      message: content ?? msg.message,
      createdAt: msg.createdAt,
      isMe: msg.isMe,
      type: msg.type,
      role: msg.role,
      roleColor: msg.roleColor,
      replyTo: msg.replyTo,
      imageUrl: msg.imageUrl,
      thumbnailUrl: msg.thumbnailUrl,
      category: msg.category,
      reactions: reactions ?? msg.reactions,
      isPinned: isPinned ?? msg.isPinned,
      isSending: isSending ?? msg.isSending,
      hasError: hasError ?? msg.hasError,
    );

    final updatedList = List<ChatMessage>.from(state.messages);
    updatedList[index] = updatedMsg;
    if (!isClosed) emit(state.copyWith(messages: updatedList));
  }

  void retryMessage(ChatMessage message, {required bool isOrganizer, required bool isPremium}) {
    emit(state.copyWith(
        messages: state.messages.where((m) => m.id != message.id).toList()));
    sendMessage(message.message, isOrganizer: isOrganizer, isPremium: isPremium);
  }

  void setCategory(String? category) {
    if (category == null) {
      emit(state.copyWith(clearCategory: true));
    } else {
      emit(state.copyWith(selectedCategory: category));
    }
    refresh();
  }

  void setMentionedMedia(ForumMedia? media) {
    if (media == null) {
      emit(state.copyWith(clearMentionedMedia: true));
    } else {
      emit(state.copyWith(mentionedMedia: media));
    }
  }

  void saveLinkPreview(String url, LinkPreviewData data) {
    final updated = Map<String, LinkPreviewData>.from(state.linkPreviews);
    updated[url] = data;
    emit(state.copyWith(linkPreviews: updated));
  }

  String? _extractCategory(String text) {
    if (text.contains('#Urgent')) return 'Urgent';
    if (text.contains('#Activity')) return 'Activity';
    if (text.contains('#Q&A')) return 'Q&A';
    if (text.contains('#Resources')) return 'Resources';
    if (text.contains('#Rules')) return 'Rules';
    return null;
  }

  @override
  Future<void> close() {
    _searchTimer?.cancel();
    return super.close();
  }
}
