import 'package:lynk_core/core.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/data/repositories/repositories.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/core/sync/sync_item.dart';
import 'package:lynk_x/core/sync/sync_manager.dart';
import 'package:lynk_x/core/utils/storage_utils.dart';
import 'package:lynk_x/core/utils/embedding_manager.dart';
import 'package:lynk_x/core/utils/i_embedding_service.dart';
import 'base_message_cubit.dart';
import 'forum_chat_state.dart';

class ForumChatCubit extends BaseMessageCubit<ForumChatState> {
  final ForumRepository _repo;
  final IEmbeddingService _embeddingService;
  Timer? _typingThrottle;
  Timer? _hideTypingTimer;
  DateTime? forumCreatedAt;
  String? channelId;
  DateTime? channelCreatedAt;

  ForumChatCubit({
    required super.forumId,
    required super.userId,
    required super.userName,
    this.forumCreatedAt,
    this.channelId,
    this.channelCreatedAt,
    required ForumRepository repo,
    IEmbeddingService? embeddingService,
    RealtimeChannel? channel,
  })  : _repo = repo,
        _embeddingService = embeddingService ?? EmbeddingManager.instance,
        super(
          messageType: 'chat',
          messageTypes: const ['chat', 'livechat_poll', 'livechat_quiz'],
          initialState: const ForumChatState(),
          channel: channel ?? Supabase.instance.client.channel('forum_chat_$forumId'),
        );

  @override
  ForumChatState copyWithState({
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
    _setupChatListeners();
    setupBaseListeners();
    await refresh();
    hasCompletedInitialRefresh = true;
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

  void _setupChatListeners() {
    channel?.onBroadcast(
      event: 'typing',
      callback: (payload) {
        if (payload['user_id'] != userId) {
          if (!isClosed) emit(state.copyWith(isTyping: true));
          _hideTypingTimer?.cancel();
          _hideTypingTimer = Timer(const Duration(seconds: 3), () {
            if (!isClosed) emit(state.copyWith(isTyping: false));
          });
        }
      },
    );
  }

  @override
  Future<void> refresh() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true));
    try {
      // Reads go through vw_forum_messages — it pre-shapes user_profile,
      // forum_members, and forum_media for ChatMessage.fromMap. Direct embeds
      // on forum_messages.forum_messages don't work because there is no FK
      // from forum_messages to forum_members.
      final data = await _repo.getMessages(
        forumId: forumId,
        limit: 20,
        before: null,
        searchQuery: state.searchQuery,
        messageTypes: messageTypes,
      );

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
        reconcileSendingMessages();
      }
    } catch (e, stack) {
      debugPrint('[ForumChatCubit] Error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(isLoading: false));
    }
  }

  @override
  Future<void> loadMore() async {
    if (state.isLoading || isClosed) return;
    emit(state.copyWith(isLoading: true));
    try {
      final oldest = state.messages.isNotEmpty
          ? state.messages.last.createdAt.toIso8601String()
          : null;

      final data = await _repo.getMessages(
        forumId: forumId,
        limit: 20,
        before: oldest,
        searchQuery: state.searchQuery,
        messageTypes: messageTypes,
      );

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
      debugPrint('[ForumChatCubit] Error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(isLoading: false));
    }
  }

  @override
  void sendMessage(String text,
      {required bool isOrganizer, required bool isPremium}) async {
    final messageId = BaseMessageCubit.uuid.v4();
    final now = DateTime.now();
    final replyTo = state.replyingTo;
    final mediaId = state.mentionedMedia?.id;
    final imageUrl = state.mentionedMedia?.url;
    final thumbnailUrl = state.mentionedMedia?.thumbnailUrl;

    // Extract #hashtag from text if present.
    const validHashtags = ['Urgent', 'Activity', 'Q&A', 'Resources', 'Rules'];
    String? category;
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
      type: MessageType.chat,
      replyTo: replyTo,
      imageUrl: imageUrl,
      thumbnailUrl: thumbnailUrl,
      category: category,
      isSending: true,
    );

    emit(state.copyWith(
      messages: [newMessage, ...state.messages],
      clearReplyTo: true,
      clearMentionedMedia: true,
    ));



    if (userId != kGuestUserId) {
      // Send the explicit `created_at` we generated locally so:
      //  (a) the broadcast and the DB row share the same timestamp (prevents
      //      cross-client divergence on subsequent UPDATE/DELETE),
      //  (b) the partition-keyed FKs to media_id and reply_to_id resolve.
      // Both forum_media and forum_messages are partitioned by created_at and
      // their FKs are composite (id, created_at) — partial keys never match.
      final mediaCreatedAt = state.mentionedMedia?.createdAt.toIso8601String();
      final replyCreatedAt = replyTo?.createdAt.toIso8601String();
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
          'message_type': 'chat',
          'hashtag': category,
          'created_at': messageCreatedAt,
          if (mediaId != null) 'media_id': mediaId,
          if (mediaCreatedAt != null) 'media_created_at': mediaCreatedAt,
          if (replyTo != null) 'reply_to_id': replyTo.id,
          if (replyCreatedAt != null) 'reply_to_created_at': replyCreatedAt,
        },
      ));

      // Broadcast immediately (Optimistic Broadcast)
      channel?.sendBroadcastMessage(
        event: 'new_message',
        payload: {
          'id': messageId,
          'author_id': userId,
          'content': text,
          'message_type': 'chat',
          'hashtag': category,
          'created_at': now.toIso8601String(),
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
          'forum_members': {'role_id': isOrganizer ? 'organizer' : 'member'}
        },
      );
    }
  }



  void notifyTyping() {
    if (_typingThrottle?.isActive ?? false) return;
    channel?.sendBroadcastMessage(
      event: 'typing',
      payload: {
        'user_id': userId,
        'user_name': userName,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    _typingThrottle = Timer(const Duration(seconds: 3), () {});
  }

  @override
  ForumChatState? fromJson(Map<String, dynamic> json) => ForumChatState.fromMap(json, userId);

  @override
  Map<String, dynamic>? toJson(ForumChatState state) => state.toJson();

  @override
  String get id => forumId;

  @override
  Future<void> reconcileMissedMessages(String afterTimestamp) async {
    try {
      final data = await _repo.getMessages(
        forumId: forumId,
        limit: 100,
        after: afterTimestamp,
        messageTypes: messageTypes,
      );

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
      debugPrint('[ForumChatCubit] Error during delta sync: $e\n$stack');
    }
  }

  @override
  Future<void> close() {
    _typingThrottle?.cancel();
    _hideTypingTimer?.cancel();
    return super.close();
  }
}
