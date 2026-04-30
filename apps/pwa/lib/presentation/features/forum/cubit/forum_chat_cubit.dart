import 'package:lynk_core/core.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/core/sync/sync_item.dart';
import 'package:lynk_x/core/sync/sync_manager.dart';
import 'base_message_cubit.dart';
import 'forum_chat_state.dart';

class ForumChatCubit extends BaseMessageCubit<ForumChatState> {
  Timer? _typingThrottle;
  Timer? _hideTypingTimer;
  StreamSubscription? _syncSubscription;

  ForumChatCubit({
    required super.forumId,
    required super.userId,
    required super.userName,
    super.channel,
  }) : super(
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
      var query = Supabase.instance.client
          .schema('forum_messages')
          .from('forum_messages')
          .select(
              '*, user_profile!author_id(user_name, is_premium), forum_members!inner(role_id)')
          .eq('forum_id', forumId)
          .eq('message_type', 'chat');

      if (state.searchQuery.isNotEmpty) {
        query = query.textSearch('fts', state.searchQuery, config: 'english');
      }

      final data = await query
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(20);
      final messages =
          data.map((json) => ChatMessage.fromMap(json, userId)).toList();

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
    final startIndex = state.messages.length;
    try {
      var query = Supabase.instance.client
          .schema('forum_messages')
          .from('forum_messages')
          .select(
              '*, user_profile!author_id(user_name, is_premium), forum_members!inner(role_id)')
          .eq('forum_id', forumId)
          .eq('message_type', 'chat');

      if (state.searchQuery.isNotEmpty) {
        query = query.textSearch('fts', state.searchQuery, config: 'english');
      }

      final data = await query
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .range(startIndex, startIndex + 20);

      final more =
          data.map((json) => ChatMessage.fromMap(json, userId)).toList();

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
      isSending: true,
    );

    emit(state.copyWith(
      messages: [newMessage, ...state.messages],
      clearReplyTo: true,
      clearMentionedMedia: true,
    ));

    if (userId != kGuestUserId) {
      // Optimistic Sync Push
      SyncManager.instance.addWork(SyncItem(
        id: messageId,
        table: 'forum_messages',
        schema: 'forum_messages',
        action: SyncAction.insert,
        payload: {
          'id': messageId,
          'forum_id': forumId,
          'author_id': userId,
          'content': text,
          'message_type': 'chat',
          if (mediaId != null) 'media_id': mediaId,
          if (replyTo != null) 'reply_to_id': replyTo.id,
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
