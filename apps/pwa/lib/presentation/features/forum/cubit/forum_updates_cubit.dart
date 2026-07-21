import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/core/utils/storage_utils.dart';
import 'base_message_cubit.dart';
import 'forum_updates_state.dart';
import 'package:lynk_x/core/sync/sync_manager.dart';
import 'package:lynk_x/core/sync/sync_item.dart';
import 'package:lynk_x/core/utils/embedding_manager.dart';
import 'package:lynk_x/core/utils/i_embedding_service.dart';

class ForumUpdatesCubit extends BaseMessageCubit<ForumUpdatesState> {
  final IEmbeddingService _embeddingService;
  DateTime? forumCreatedAt;
  String? channelId;
  DateTime? channelCreatedAt;

  ForumUpdatesCubit({
    required super.forumId,
    required super.userId,
    required super.userName,
    this.forumCreatedAt,
    this.channelId,
    this.channelCreatedAt,
    IEmbeddingService? embeddingService,
    RealtimeChannel? channel,
  })  : _embeddingService = embeddingService ?? EmbeddingManager.instance,
        super(
          messageType: 'announcement',
          messageTypes: const ['announcement', 'update_poll', 'update_quiz'],
          initialState: const ForumUpdatesState(),
          channel: channel ?? Supabase.instance.client.channel('forum_updates_$forumId'),
        );

  @override
  ForumUpdatesState copyWithState({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? searchQuery,
    ChatMessage? replyingTo,
    bool clearReplyTo = false,
    ChatMessage? editingMessage,
    bool clearEditingMessage = false,
    ForumMedia? mentionedMedia,
    bool clearMentionedMedia = false,
    Map<String, LinkPreviewData>? linkPreviews,
    bool? showJumpToBottom,
  }) {
    return state.copyWith(
      messages: messages,
      isLoading: isLoading,
      searchQuery: searchQuery,
      replyingTo: replyingTo,
      clearReplyTo: clearReplyTo,
      editingMessage: editingMessage,
      clearEditingMessage: clearEditingMessage,
      mentionedMedia: mentionedMedia,
      clearMentionedMedia: clearMentionedMedia,
      linkPreviews: linkPreviews,
      showJumpToBottom: showJumpToBottom,
    );
  }

  Future<void> init() async {
    setupBaseListeners();
    await refresh();
  }

  void syncForumContext({
    required DateTime? forumCreatedAt,
    String? channelId,
    DateTime? channelCreatedAt,
  }) {
    this.forumCreatedAt = forumCreatedAt;
    this.channelId = channelId;
    this.channelCreatedAt = channelCreatedAt;
  }

  @override
  Future<void> refresh() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true));
    try {
      var query = Supabase.instance.client
          .from('vw_forum_messages')
          .select()
          .eq('forum_id', forumId)
          .inFilter('message_type', messageTypes)
          .filter('deleted_at', 'is', null);

      if (state.selectedCategory != null) {
        query = query.eq('hashtag', state.selectedCategory!);
      }

      if (state.searchQuery.isNotEmpty) {
        query = query.textSearch('fts', state.searchQuery, config: 'english');
      }

      final data = await query
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(20);
      var messages =
          data.map((json) => ChatMessage.fromMap(json, userId)).toList();

      final mediaMessages = messages.where((m) => m.imageUrl != null && m.imageUrl!.isNotEmpty).toList();
      if (mediaMessages.isNotEmpty) {
        final urls = mediaMessages.map((m) => m.imageUrl!).toList();
        final signedMap = await batchSignStorageUrls(urls, 'forum_media');
        messages = messages.map((m) {
          if (m.imageUrl != null && m.imageUrl!.isNotEmpty) {
            final path = getPathFromStorageUrl(m.imageUrl!, 'forum_media');
            final signed = signedMap[path];
            if (signed != null) {
              return m.copyWith(imageUrl: signed, thumbnailUrl: signed);
            }
          }
          return m;
        }).toList();
      }

      if (!isClosed) {
        emit(state.copyWith(messages: messages, isLoading: false));
      }
    } catch (e, stack) {
      debugPrint('[ForumUpdatesCubit] Error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(isLoading: false));
    }
  }

  @override
  Future<void> loadMore() async {
    if (state.isLoading || isClosed) return;
    emit(state.copyWith(isLoading: true));
    final startIndex = state.messages.length;
    try {
      var query = Supabase.instance.client
          .from('vw_forum_messages')
          .select()
          .eq('forum_id', forumId)
          .inFilter('message_type', messageTypes)
          .filter('deleted_at', 'is', null);

      if (state.selectedCategory != null) {
        query = query.eq('hashtag', state.selectedCategory!);
      }

      if (state.searchQuery.isNotEmpty) {
        query = query.textSearch('fts', state.searchQuery, config: 'english');
      }

      final data = await query
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .range(startIndex, startIndex + 20);

      var more =
          data.map((json) => ChatMessage.fromMap(json, userId)).toList();

      final mediaMessages = more.where((m) => m.imageUrl != null && m.imageUrl!.isNotEmpty).toList();
      if (mediaMessages.isNotEmpty) {
        final urls = mediaMessages.map((m) => m.imageUrl!).toList();
        final signedMap = await batchSignStorageUrls(urls, 'forum_media');
        more = more.map((m) {
          if (m.imageUrl != null && m.imageUrl!.isNotEmpty) {
            final path = getPathFromStorageUrl(m.imageUrl!, 'forum_media');
            final signed = signedMap[path];
            if (signed != null) {
              return m.copyWith(imageUrl: signed, thumbnailUrl: signed);
            }
          }
          return m;
        }).toList();
      }

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

  void setCategory(String? category) {
    if (!isClosed) {
      emit(state.copyWith(selectedCategory: category, clearCategory: category == null));
    }
    refresh();
  }

  @override
  void sendMessage(String text,
      {required bool isOrganizer, required bool isPremium}) async {
    if (!isOrganizer) return; // Only organizers send updates
    final messageId = BaseMessageCubit.uuid.v4();
    final now = DateTime.now();
    final mediaId = state.mentionedMedia?.id;
    final imageUrl = state.mentionedMedia?.url;
    final thumbnailUrl = state.mentionedMedia?.thumbnailUrl;

    // Extract #hashtag from text if present, otherwise fall back to selected filter.
    const validHashtags = ['Urgent', 'Activity', 'Q&A', 'Resources', 'Rules'];
    String? category = state.selectedCategory;
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('#')) {
      final tagPart = trimmed.substring(1).trimLeft();
      for (final tag in validHashtags) {
        final escapedTag = RegExp.escape(tag);
        final regExp = RegExp('^$escapedTag(?:\\s|[.,!?]|\$)', caseSensitive: false);
        if (regExp.hasMatch(tagPart)) {
          category = tag;
          break;
        }
      }
    }

    final newMessage = ChatMessage(
      id: messageId,
      sender: userName,
      userId: userId,
      message: text,
      createdAt: now,
      isMe: true,
      type: MessageType.announcement,
      category: category,
      imageUrl: imageUrl,
      thumbnailUrl: thumbnailUrl,
      isSending: true,
    );

    emit(state.copyWith(
      messages: [newMessage, ...state.messages],
      clearMentionedMedia: true,
    ));

    // forum_media is partitioned by created_at; the FK on forum_messages is
    // composite (media_id, media_created_at) — both must be supplied or the
    // FK will not resolve and media will not render in the message.
    final mediaCreatedAt = state.mentionedMedia?.createdAt.toIso8601String();
    final messageCreatedAt = now.toIso8601String();

    // Trigger client-side background embedding calculation
    _embeddingService.processMessage(messageId, text);

    SyncManager.instance.addWork(SyncItem(
      id: messageId,
      table: 'forum_messages',
      schema: 'social',
      action: SyncAction.insert,
      partitionKeyName: 'created_at',
      partitionKeyValue: messageCreatedAt,
      payload: {
        'id': messageId,
        'forum_id': forumId,
        'forum_created_at': forumCreatedAt?.toIso8601String(),
        if (channelId != null) 'channel_id': channelId,
        if (channelCreatedAt != null) 'channel_created_at': channelCreatedAt?.toIso8601String(),
        'author_id': userId,
        'content': text,
        'message_type': 'announcement',
        'hashtag': category,
        'created_at': messageCreatedAt,
        if (mediaId != null) 'media_id': mediaId,
        if (mediaCreatedAt != null) 'media_created_at': mediaCreatedAt,
      },
    ));

    // Broadcast
    channel?.sendBroadcastMessage(
      event: 'new_message',
      payload: {
        'id': messageId,
        'author_id': userId,
        'content': text,
        'message_type': 'announcement',
        'hashtag': category,
        'created_at': messageCreatedAt,
        if (mediaId != null) 'media_id': mediaId,
        if (imageUrl != null)
          'forum_media': {
            'url': imageUrl,
            'thumbnail_url': thumbnailUrl,
          },
        'user_profile': {
          'full_name': userName,
          'is_premium': isPremium,
        },
        'forum_members': {'role_id': 'organizer'}
      },
    );
  }

  @override
  Future<void> reconcileMissedMessages(String afterTimestamp) async {
    try {
      var query = Supabase.instance.client
          .from('vw_forum_messages')
          .select()
          .eq('forum_id', forumId)
          .inFilter('message_type', messageTypes)
          .gt('created_at', afterTimestamp);

      if (state.selectedCategory != null) {
        query = query.eq('hashtag', state.selectedCategory!);
      }

      final data = await query
          .order('created_at', ascending: false)
          .limit(100);

      final deletedIds = data
          .where((json) => json['deleted_at'] != null)
          .map((json) => json['id'] as String)
          .toSet();

      final activeData = data.where((json) => json['deleted_at'] == null).toList();

      var newMsgs = activeData.map((json) => ChatMessage.fromMap(json, userId)).toList();

      final mediaMessages = newMsgs.where((m) => m.imageUrl != null && m.imageUrl!.isNotEmpty).toList();
      if (mediaMessages.isNotEmpty) {
        final urls = mediaMessages.map((m) => m.imageUrl!).toList();
        final signedMap = await batchSignStorageUrls(urls, 'forum_media');
        newMsgs = newMsgs.map((m) {
          if (m.imageUrl != null && m.imageUrl!.isNotEmpty) {
            final path = getPathFromStorageUrl(m.imageUrl!, 'forum_media');
            final signed = signedMap[path];
            if (signed != null) {
              return m.copyWith(imageUrl: signed, thumbnailUrl: signed);
            }
          }
          return m;
        }).toList();
      }

      final updatedList = List<ChatMessage>.from(state.messages);
      for (final msg in newMsgs) {
        if (!updatedList.any((m) => m.id == msg.id)) {
          updatedList.add(msg);
        }
      }

      if (deletedIds.isNotEmpty) {
        updatedList.removeWhere((m) => deletedIds.contains(m.id));
      }

      updatedList.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!isClosed) emit(state.copyWith(messages: updatedList));
    } catch (e, stack) {
      debugPrint('[ForumUpdatesCubit] Error during delta sync: $e\n$stack');
    }
  }

  @override
  ForumUpdatesState? fromJson(Map<String, dynamic> json) => ForumUpdatesState.fromMap(json, userId);

  @override
  Map<String, dynamic>? toJson(ForumUpdatesState state) => state.toJson();

  @override
  String get id => forumId;
}
