import 'dart:async';
import 'package:lynk_core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/core/utils/storage_utils.dart';
import 'base_message_state.dart';

abstract class BaseMessageCubit<T extends BaseMessageState> extends HydratedCubit<T> {
  static const uuid = Uuid();
  
  final String forumId;
  final String userId;
  final String userName;
  final RealtimeChannel? channel;
  final String messageType;

  Timer? searchTimer;

  BaseMessageCubit({
    required this.forumId,
    required this.userId,
    required this.userName,
    this.channel,
    required this.messageType,
    required T initialState,
  }) : super(initialState);

  /// Must be provided by children to yield a new state.
  T copyWithState({
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
  });

  /// Base listeners.
  void setupBaseListeners() {
    if (channel == null) return;
    channel?.onBroadcast(
      event: 'new_message',
      callback: (payload) {
        if (payload.isEmpty) return;
        final msg = ChatMessage.fromMap(payload, userId);
        if (msg.type == _getTypeEnum(messageType)) {
          onBroadcastMessageReceived(msg);
        }
      },
    );

    channel?.onBroadcast(
      event: 'edit_message',
      callback: (payload) {
        final String? msgId = payload['id'] as String?;
        final String? content = payload['content'] as String?;
        if (msgId != null && content != null) {
          updateMessageInPlace(msgId, content: content);
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

          updateMessageInPlace(msgId, reactions: updatedReactions);
        }
      },
    );

    channel?.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'social',
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
          if (!isClosed) emit(copyWithState(messages: updated));
        } else if (payload.eventType == PostgresChangeEvent.insert) {
          final data = payload.newRecord;
          if (data['message_type'] != messageType) return;

          final id = data['id'] as String;
          if (state.messages.any((m) => m.id == id)) return;

          final msg = ChatMessage.fromMap(data, userId);
          onBroadcastMessageReceived(msg);
        } else if (payload.eventType == PostgresChangeEvent.update) {
          final data = payload.newRecord;
          if (data['message_type'] != messageType) return;

          if (data['deleted_at'] != null) {
            final id = data['id'] as String?;
            final updated = state.messages.where((m) => m.id != id).toList();
            if (!isClosed) emit(copyWithState(messages: updated));
          } else {
            updateMessageInPlace(
              data['id'] as String,
              content: data['content'] as String?,
              isPinned: data['is_pinned'] == true,
            );
          }
        }
      },
    );
    // Do NOT call channel?.subscribe() here — ForumCubit owns the channel
    // lifecycle and has already subscribed it. Re-subscribing fires duplicate
    // CDC callbacks and triggers spurious refresh() calls.
  }

  MessageType _getTypeEnum(String type) {
    if (type == 'chat') return MessageType.chat;
    if (type == 'announcement') return MessageType.announcement;
    return MessageType.chat;
  }

  void onBroadcastMessageReceived(ChatMessage msg) {
    if (msg.userId == userId) return;
    if (state.messages.any((m) => m.id == msg.id)) return;
    if (msg.imageUrl != null && msg.imageUrl!.isNotEmpty) {
      _signMessageUrlAndEmit(msg);
    } else {
      if (!isClosed) emit(copyWithState(messages: [msg, ...state.messages]));
    }
  }

  Future<void> _signMessageUrlAndEmit(ChatMessage msg) async {
    try {
      final path = getPathFromStorageUrl(msg.imageUrl!, 'forum_media');
      if (path.isNotEmpty) {
        final signedUrl = await Supabase.instance.client.storage
            .from('forum_media')
            .createSignedUrl(path, 7200);
        final updatedMsg = msg.copyWith(
          imageUrl: signedUrl,
          thumbnailUrl: signedUrl,
        );
        if (!isClosed) emit(copyWithState(messages: [updatedMsg, ...state.messages]));
      } else {
        if (!isClosed) emit(copyWithState(messages: [msg, ...state.messages]));
      }
    } catch (_) {
      if (!isClosed) emit(copyWithState(messages: [msg, ...state.messages]));
    }
  }

  Future<void> refresh();

  Future<void> loadMore();

  void setSearchQuery(String query) {
    if (!isClosed) emit(copyWithState(searchQuery: query));
    searchTimer?.cancel();
    searchTimer = Timer(const Duration(milliseconds: 300), () {
      refresh();
    });
  }

  /// Soft-deletes a message. `forum_messages.forum_messages` is partitioned by
  /// `created_at` with composite PK (id, created_at), so the message's
  /// `createdAt` must be in the WHERE clause or the UPDATE matches no rows.
  Future<void> deleteMessage(ChatMessage message) async {
    final originalMessages = List<ChatMessage>.from(state.messages);
    if (!isClosed) emit(copyWithState(messages: state.messages.where((m) => m.id != message.id).toList()));

    try {
      if (userId == kGuestUserId) return;
      await Supabase.instance.client
          .schema('social').from('forum_messages')
          .update({'deleted_at': DateTime.now().toIso8601String()})
          .eq('id', message.id)
          .eq('created_at', message.createdAt.toIso8601String());
      await refresh();
    } catch (e, stack) {
      debugPrint('[BaseMessageCubit] Error deleting msg: $e\n$stack');
      if (!isClosed) emit(copyWithState(messages: originalMessages));
    }
  }

  void setEditingMessage(ChatMessage? message) {
    if (message == null) {
      if (!isClosed) emit(copyWithState(clearEditingMessage: true));
    } else {
      if (!isClosed) emit(copyWithState(editingMessage: message));
    }
  }

  Future<void> editMessage(ChatMessage message, String newContent) async {
    final originalMessages = List<ChatMessage>.from(state.messages);
    updateMessageInPlace(message.id, content: newContent);

    try {
      if (userId == kGuestUserId) return;
      await Supabase.instance.client
          .schema('social').from('forum_messages')
          .update({'content': newContent})
          .eq('id', message.id)
          .eq('created_at', message.createdAt.toIso8601String());

      channel?.sendBroadcastMessage(
        event: 'edit_message',
        payload: {
          'id': message.id,
          'content': newContent,
        },
      );
    } catch (e, stack) {
      debugPrint('[BaseMessageCubit] Error editing msg: $e\n$stack');
      if (!isClosed) emit(copyWithState(messages: originalMessages));
    }
  }

  void setReplyTo(ChatMessage? message) {
    if (message == null) {
      if (!isClosed) emit(copyWithState(clearReplyTo: true));
    } else {
      if (!isClosed) emit(copyWithState(replyingTo: message));
    }
  }

  void setMentionedMedia(ForumMedia? media) {
    if (media == null) {
      if (!isClosed) emit(copyWithState(clearMentionedMedia: true));
    } else {
      if (!isClosed) emit(copyWithState(mentionedMedia: media));
    }
  }

  void saveLinkPreview(String url, LinkPreviewData data) {
    final updated = Map<String, LinkPreviewData>.from(state.linkPreviews);
    updated[url] = data;
    if (!isClosed) emit(copyWithState(linkPreviews: updated));
  }

  void setJumpToBottom(bool show) {
    if (show != state.showJumpToBottom) {
      if (!isClosed) emit(copyWithState(showJumpToBottom: show));
    }
  }

  /// Reports a forum message via the canonical `submit_report` RPC.
  /// `forum_messages.forum_messages` is partitioned, so the report row's FK
  /// to the message uses the composite (target_message_id, target_message_created_at).
  Future<void> reportMessage(ChatMessage message, String reason) async {
    try {
      if (userId == kGuestUserId) return;
      await Supabase.instance.client.rpc('submit_report', params: {
        'p_target_message_id': message.id,
        'p_target_message_created_at': message.createdAt.toIso8601String(),
        'p_reason_id': 'general_abuse',
        'p_description': reason,
      });
    } catch (e, stack) {
      debugPrint('[BaseMessageCubit] Error reporting msg: $e\n$stack');
    }
  }

  void updateMessageInPlace(String messageId, {
    String? content,
    bool? isPinned,
    Map<String, int>? reactions,
  }) {
    final index = state.messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final oldMsg = state.messages[index];
      final newMsg = oldMsg.copyWith(
        message: content ?? oldMsg.message,
        reactions: reactions ?? oldMsg.reactions,
        isPinned: isPinned ?? oldMsg.isPinned,
      );

      final updated = List<ChatMessage>.from(state.messages);
      updated[index] = newMsg;
      if (!isClosed) emit(copyWithState(messages: updated));
    }
  }

  @override
  Future<void> close() {
    searchTimer?.cancel();
    return super.close();
  }
}
