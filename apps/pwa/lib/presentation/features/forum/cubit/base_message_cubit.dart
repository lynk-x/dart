import 'dart:async';
import 'package:lynk_core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'base_message_state.dart';

abstract class BaseMessageCubit<T extends BaseMessageState> extends Cubit<T> {
  static const uuid = Uuid();
  
  final String forumId;
  final String userId;
  final String userName;
  final RealtimeChannel? channel;
  final String messageType;

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
    ForumMedia? mentionedMedia,
    bool clearMentionedMedia = false,
    Map<String, LinkPreviewData>? linkPreviews,
  });

  /// Base listeners. Note: If subclasses override or need custom listeners,
  /// they must handle them or call super._setupBaseListeners.
  void setupBaseListeners() {
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
          if (!isClosed) emit(copyWithState(messages: updated));
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

    channel?.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        refresh();
      }
    });
  }

  MessageType _getTypeEnum(String type) {
    if (type == 'chat') return MessageType.chat;
    if (type == 'announcement') return MessageType.announcement;
    return MessageType.chat;
  }

  void onBroadcastMessageReceived(ChatMessage msg) {
    if (msg.userId == userId) return;
    if (state.messages.any((m) => m.id == msg.id)) return;
    emit(copyWithState(messages: [msg, ...state.messages]));
  }

  /// Must be implemented by child classes
  Future<void> refresh();

  Future<void> deleteMessage(String messageId) async {
    final originalMessages = List<ChatMessage>.from(state.messages);
    emit(copyWithState(messages: state.messages.where((m) => m.id != messageId).toList()));

    try {
      if (userId == kGuestUserId) return;
      await Supabase.instance.client
          .from('forum_messages')
          .update({'deleted_at': DateTime.now().toIso8601String()}).eq(
              'id', messageId);
      await refresh();
    } catch (e, stack) {
      debugPrint('[BaseMessageCubit] Error deleting msg: $e\n$stack');
      if (!isClosed) emit(copyWithState(messages: originalMessages));
    }
  }

  Future<void> reportMessage(String messageId, String reason) async {
    try {
      if (userId == kGuestUserId) return;
      await Supabase.instance.client.rpc('report_content', params: {
        'p_content_type': 'message',
        'p_content_id': messageId,
        'p_reported_by': userId,
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
      final newMsg = ChatMessage(
        id: oldMsg.id,
        sender: oldMsg.sender,
        userId: oldMsg.userId,
        message: content ?? oldMsg.message,
        createdAt: oldMsg.createdAt,
        isMe: oldMsg.isMe,
        type: oldMsg.type,
        role: oldMsg.role,
        roleColor: oldMsg.roleColor,
        replyTo: oldMsg.replyTo,
        imageUrl: oldMsg.imageUrl,
        thumbnailUrl: oldMsg.thumbnailUrl,
        linkPreviewTitle: oldMsg.linkPreviewTitle,
        linkPreviewUrl: oldMsg.linkPreviewUrl,
        targetRoute: oldMsg.targetRoute,
        category: oldMsg.category,
        reactions: reactions ?? oldMsg.reactions,
        isSending: oldMsg.isSending,
        hasError: oldMsg.hasError,
        isPinned: isPinned ?? oldMsg.isPinned,
      );

      final updated = List<ChatMessage>.from(state.messages);
      updated[index] = newMsg;
      if (!isClosed) emit(copyWithState(messages: updated));
    }
  }
}
