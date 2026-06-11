import 'package:lynk_core/core.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:lynk_x/data/repositories/repositories.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/core/sync/sync_item.dart';
import 'package:lynk_x/core/sync/sync_manager.dart';
import 'package:lynk_x/core/utils/storage_utils.dart';
import 'base_message_cubit.dart';
import 'forum_chat_state.dart';

class ForumChatCubit extends BaseMessageCubit<ForumChatState> {
  final ForumRepository _repo;
  Timer? _typingThrottle;
  Timer? _hideTypingTimer;
  StreamSubscription? _syncSubscription;
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
    super.channel,
  })  : _repo = repo,
        super(
          messageType: 'chat',
          initialState: const ForumChatState(),
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
    await refresh();
    _setupChatListeners();
    setupBaseListeners();
    _setupSyncListener();
  }

  void _setupSyncListener() {
    _syncSubscription = SyncManager.instance.statusStream.listen((statusMap) {
      for (var entry in statusMap.entries) {
        if (entry.value) {
          _completeMessage(entry.key);
        } else {
          _failMessage(entry.key);
        }
      }
    });
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
      );

      // Apply search filter client-side if query is active
      // (repo doesn't expose fts search; keep it simple for now)
      final filtered = state.searchQuery.isNotEmpty
          ? data
              .where((m) =>
                  (m['content'] as String? ?? '')
                      .toLowerCase()
                      .contains(state.searchQuery.toLowerCase()))
              .toList()
          : data;

      var messages =
          filtered.map((json) => ChatMessage.fromMap(json, userId)).toList();

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

  void _completeMessage(String id) {
    _updateMessageInPlaceInternal(id, isSending: false, hasError: false);
  }

  void _failMessage(String id) {
    _updateMessageInPlaceInternal(id, isSending: false, hasError: true);
  }

  void _updateMessageInPlaceInternal(
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
    final updatedMsg = msg.copyWith(
      message: content ?? msg.message,
      reactions: reactions ?? msg.reactions,
      isPinned: isPinned ?? msg.isPinned,
      isSending: isSending ?? msg.isSending,
      hasError: hasError ?? msg.hasError,
    );

    final updatedList = List<ChatMessage>.from(state.messages);
    updatedList[index] = updatedMsg;
    if (!isClosed) emit(state.copyWith(messages: updatedList));
  }

  void retryMessage(ChatMessage message,
      {required bool isOrganizer, required bool isPremium}) {
    emit(state.copyWith(
        messages: state.messages.where((m) => m.id != message.id).toList()));
    sendMessage(message.message, isOrganizer: isOrganizer, isPremium: isPremium);
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
  Future<void> close() {
    _typingThrottle?.cancel();
    _hideTypingTimer?.cancel();
    _syncSubscription?.cancel();
    return super.close();
  }
}
