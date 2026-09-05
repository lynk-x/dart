import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:lynk_core/core.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/core/utils/storage_utils.dart';
import 'package:lynk_x/core/sync/sync_manager.dart';
import 'package:lynk_x/presentation/features/forum/services/stream_service.dart';
import 'package:lynk_x/presentation/features/forum/services/mini_overlay_service.dart';
import 'package:lynk_x/presentation/features/forum/services/forum_cdc_service.dart';
import 'base_message_state.dart';

abstract class BaseMessageCubit<T extends BaseMessageState> extends HydratedCubit<T> {
  static const uuid = Uuid();
  
  final String forumId;
  final String userId;
  final String userName;
  final RealtimeChannel? channel;
  // The primary type a message sent from this tab gets (used by sendMessage);
  // messageTypes is the full set this tab renders/subscribes to — e.g. Live
  // Chat renders 'chat' plus 'livechat_poll'/'livechat_quiz' (a poll/quiz
  // created from its '+' button), Updates renders 'announcement' plus
  // 'update_poll'/'update_quiz'.
  final String messageType;
  final List<String> messageTypes;

  Timer? searchTimer;
  /// Stored function reference for [ForumCdcService] — must be the same object
  /// used in both [register] and [unregister] calls.
  void Function(PostgresChangePayload)? _cdcListener;
  StreamSubscription? _syncSubscription;
  bool _wasDisconnected = false;

  /// Snapshot taken before the first search query so we can restore it
  /// on query-clear without a network round-trip.
  List<ChatMessage> _preSearchMessages = const [];

  /// Maximum number of messages kept in memory state during live sessions.
  /// Prevents unbounded heap growth in busy streams; older items load on demand.
  static const int maxInMemoryMessages = 100;

  bool hasCompletedInitialRefresh = false;

  BaseMessageCubit({
    required this.forumId,
    required this.userId,
    required this.userName,
    this.channel,
    required this.messageType,
    List<String>? messageTypes,
    required T initialState,
  })  : messageTypes = messageTypes ?? [messageType],
        super(initialState);

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
    _setupSyncListener();
    reconcileSendingMessages();
    if (channel == null) return;

    channel?.onBroadcast(
      event: 'new_message',
      callback: (payload) {
        if (payload.isEmpty) return;
        try {
          final msg = ChatMessage.fromMap(payload, userId);
          if (messageTypes.contains(payload['message_type'])) {
            onBroadcastMessageReceived(msg);
          }
        } catch (e, stack) {
          // A malformed/unparseable broadcast is dropped rather than crashing
          // the listener, but log it — otherwise a message silently vanishes
          // from other clients' views with zero diagnostic trace.
          debugPrint('[BaseMessageCubit] new_message broadcast parse error: $e\n$stack');
        }
      },
    );

    channel?.onBroadcast(
      event: 'edit_message',
      callback: (payload) {
        try {
          final String? msgId = payload['id'] as String?;
          final String? content = payload['content'] as String?;
          final bool? isPinned = payload['is_pinned'] as bool?;
          if (msgId != null) {
            updateMessageInPlace(msgId, content: content, isPinned: isPinned);
          }
        } catch (e, stack) {
          debugPrint('[BaseMessageCubit] edit_message broadcast parse error: $e\n$stack');
        }
      },
    );

    channel?.onBroadcast(
      event: 'delete_message',
      callback: (payload) {
        try {
          final String? msgId = payload['id'] as String?;
          if (msgId != null) {
            final updated = state.messages.where((m) => m.id != msgId).toList();
            if (!isClosed) emit(copyWithState(messages: updated));
          }
        } catch (e, stack) {
          debugPrint('[BaseMessageCubit] delete_message broadcast parse error: $e\n$stack');
        }
      },
    );

    channel?.onBroadcast(
      event: 'message_reaction',
      callback: (payload) {
        try {
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
        } catch (e, stack) {
          debugPrint('[BaseMessageCubit] message_reaction broadcast parse error: $e\n$stack');
        }
      },
    );

    channel?.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        _wasDisconnected = true;
      } else if (status == RealtimeSubscribeStatus.subscribed) {
        if (_wasDisconnected) {
          _wasDisconnected = false;
          final newest = state.messages.isNotEmpty ? state.messages.first : null;
          if (newest != null) {
            reconcileMissedMessages(newest.createdAt.toIso8601String());
          }
        }
      }
    });

    // Register with the shared CDC singleton — one channel per forumId
    // regardless of how many cubits are subscribed. Each cubit filters
    // by its own messageTypes inside _handleCdcPayload.
    _cdcListener = _handleCdcPayload;
    ForumCdcService().register(forumId, _cdcListener!);
  }

  /// Handles a Postgres CDC event dispatched by [ForumCdcService].
  /// Filters by [messageTypes] so Chat and Updates cubits sharing the same
  /// channel each only act on their own message kinds.
  void _handleCdcPayload(PostgresChangePayload payload) {
    try {
      if (payload.eventType == PostgresChangeEvent.delete) {
        final id = payload.oldRecord['id'] as String?;
        final updated = state.messages.where((m) => m.id != id).toList();
        if (!isClosed) emit(copyWithState(messages: updated));
      } else if (payload.eventType == PostgresChangeEvent.insert) {
        final data = payload.newRecord;
        if (!messageTypes.contains(data['message_type'])) return;

        final id = data['id'] as String;
        final index = state.messages.indexWhere((m) => m.id == id);
        if (index != -1) {
          final existingMsg = state.messages[index];
          if (existingMsg.isSending) {
            updateMessageInPlace(id, isSending: false, hasError: false);
          }
          return;
        }

        final msg = ChatMessage.fromMap(data, userId);
        onBroadcastMessageReceived(msg);
      } else if (payload.eventType == PostgresChangeEvent.update) {
        final data = payload.newRecord;
        if (!messageTypes.contains(data['message_type'])) return;

        if (data['deleted_at'] != null) {
          final id = data['id'] as String?;
          final updated = state.messages.where((m) => m.id != id).toList();
          if (!isClosed) emit(copyWithState(messages: updated));
        } else {
          updateMessageInPlace(
            data['id'] as String,
            content: data['content'] as String?,
            isPinned: data['is_pinned'] == true,
            isSending: false,
            hasError: false,
          );
        }
      }
    } catch (e, stack) {
      debugPrint('[BaseMessageCubit] CDC payload parse error: $e\n$stack');
    }
  }

  void onBroadcastMessageReceived(ChatMessage msg) {
    _syncLogicalServicesForSystemMessage(msg);
    final index = state.messages.indexWhere((m) => m.id == msg.id);
    if (index != -1) {
      final existingMsg = state.messages[index];
      
      // Reconcile the message: if it is currently marked as sending or has unresolved/placeholder
      // sender values, update it in-place using the newly received broadcast metadata (and clear the sending flag).
      if (existingMsg.isSending ||
          existingMsg.sender == 'Deleted User' ||
          existingMsg.sender == 'Unknown' ||
          existingMsg.sender.isEmpty ||
          existingMsg.sender == existingMsg.userId) {
        final updated = List<ChatMessage>.from(state.messages);
        updated[index] = msg.copyWith(isSending: false);
        if (!isClosed) emit(copyWithState(messages: updated));
      }
      return;
    }

    // Prepend the message if it does not already exist in the list.
    // This applies to both other users' messages and our own messages received from other devices/tabs.
    if (msg.imageUrl != null && msg.imageUrl!.isNotEmpty) {
      _signMessageUrlAndEmit(msg);
    } else {
      final updated = _capMessages([msg, ...state.messages]);
      if (!isClosed) emit(copyWithState(messages: updated));
    }
  }

  List<ChatMessage> _capMessages(List<ChatMessage> msgs) {
    if (msgs.length > maxInMemoryMessages) {
      return msgs.sublist(0, maxInMemoryMessages);
    }
    return msgs;
  }

  void _syncLogicalServicesForSystemMessage(ChatMessage msg) {
    if (!msg.type.isSystem) return;
    final content = msg.message.toLowerCase();

    if (content.contains('started the live stream')) {
      ForumVideoStreamService().setLive(true);
    } else if (content.contains('ended the live stream')) {
      ForumVideoStreamService().setLive(false);
      MiniOverlayService().endPipSession();
    } else if (content.contains('ended the live call')) {
      MiniOverlayService().endPipSession();
    }
  }

  Future<void> _signMessageUrlAndEmit(ChatMessage msg) async {
    try {
      final path = getPathFromStorageUrl(msg.imageUrl!, 'forum_media');
      if (path.isNotEmpty) {
        final signedUrls = await batchSignStorageUrls([path], 'forum_media');
        final signedUrl = signedUrls[path];
        if (signedUrl != null && signedUrl.isNotEmpty) {
          final updatedMsg = msg.copyWith(
            imageUrl: signedUrl,
            thumbnailUrl: signedUrl,
          );
          final updated = _capMessages([updatedMsg, ...state.messages]);
          if (!isClosed) emit(copyWithState(messages: updated));
          return;
        }
      }
      final updated = _capMessages([msg, ...state.messages]);
      if (!isClosed) emit(copyWithState(messages: updated));
    } catch (_) {
      final updated = _capMessages([msg, ...state.messages]);
      if (!isClosed) emit(copyWithState(messages: updated));
    }
  }

  Future<void> refresh();

  Future<void> loadMore();

  Future<void> reconcileMissedMessages(String afterTimestamp);

  void setSearchQuery(String query) {
    if (!isClosed) emit(copyWithState(searchQuery: query));
    searchTimer?.cancel();

    if (query.isEmpty) {
      // Restore pre-search snapshot without a network round-trip when
      // the user clears the search field.
      if (_preSearchMessages.isNotEmpty) {
        if (!isClosed) emit(copyWithState(messages: _preSearchMessages));
        _preSearchMessages = const [];
      } else {
        // No snapshot — fall back to a normal refresh.
        refresh();
        _preSearchMessages = const [];
      }
      return;
    }

    // Capture snapshot before first search so clear can restore it.
    if (_preSearchMessages.isEmpty && state.messages.isNotEmpty) {
      _preSearchMessages = List.unmodifiable(state.messages);
    }

    searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (!isClosed) emit(copyWithState(messages: []));
      refresh();
    });
  }

  /// Soft-deletes a message. `forum_messages.forum_messages` is partitioned by
  /// `created_at` with composite PK (id, created_at), so the message's
  /// `createdAt` must be in the WHERE clause or the UPDATE matches no rows.
  Future<void> deleteMessage(ChatMessage message) async {
    if (userId == kGuestUserId) return;
    final originalMessages = List<ChatMessage>.from(state.messages);
    if (!isClosed) emit(copyWithState(messages: state.messages.where((m) => m.id != message.id).toList()));

    try {
      await Supabase.instance.client
          .schema('social').from('forum_messages')
          .update({'deleted_at': DateTime.now().toIso8601String()})
          .eq('id', message.id)
          .eq('created_at', message.createdAt.toIso8601String());

      channel?.sendBroadcastMessage(
        event: 'delete_message',
        payload: {
          'id': message.id,
        },
      );
      // No refresh() needed: the optimistic removal, broadcast to peers,
      // and CDC pipeline already guarantee consistency.
    } catch (_) {
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
    if (userId == kGuestUserId) return;
    final originalMessages = List<ChatMessage>.from(state.messages);
    updateMessageInPlace(message.id, content: newContent);

    try {
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
    } catch (_) {
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


  void updateMessageInPlace(String messageId, {
    String? content,
    bool? isPinned,
    Map<String, int>? reactions,
    bool? isSending,
    bool? hasError,
    bool? isEdited,
  }) {
    final index = state.messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final oldMsg = state.messages[index];
      final wasContentChanged = content != null && content != oldMsg.message;
      final newMsg = oldMsg.copyWith(
        message: content ?? oldMsg.message,
        reactions: reactions ?? oldMsg.reactions,
        isPinned: isPinned ?? oldMsg.isPinned,
        isSending: isSending ?? oldMsg.isSending,
        hasError: hasError ?? oldMsg.hasError,
        isEdited: isEdited ?? (wasContentChanged ? true : oldMsg.isEdited),
      );

      final updated = List<ChatMessage>.from(state.messages);
      updated[index] = newMsg;
      if (!isClosed) emit(copyWithState(messages: updated));
    }
  }

  void reconcileSendingMessages() {
    final updatedList = state.messages.map((msg) {
      if (msg.isSending && !SyncManager.instance.isQueued(msg.id)) {
        return msg.copyWith(isSending: false, hasError: false);
      }
      return msg;
    }).toList();

    if (!listEquals(updatedList, state.messages)) {
      if (!isClosed) emit(copyWithState(messages: updatedList));
    }
  }

  void _setupSyncListener() {
    _syncSubscription = SyncManager.instance.statusStream.listen((statusMap) {
      for (var entry in statusMap.entries) {
        if (entry.value) {
          updateMessageInPlace(entry.key, isSending: false, hasError: false);
        } else {
          updateMessageInPlace(entry.key, isSending: false, hasError: true);
        }
      }
    });
  }

  void retryMessage(ChatMessage message,
      {required bool isOrganizer, required bool isPremium}) {
    if (!isClosed) {
      emit(copyWithState(
          messages: state.messages.where((m) => m.id != message.id).toList()));
    }
    sendMessage(message.message, isOrganizer: isOrganizer, isPremium: isPremium);
  }

  void sendMessage(String text,
      {required bool isOrganizer, required bool isPremium, MessageType? messageType});

  @override
  Future<void> close() {
    _syncSubscription?.cancel();
    searchTimer?.cancel();
    _preSearchMessages = const [];
    if (_cdcListener != null) {
      // Unregister from the shared CDC singleton — decrements ref count;
      // channel is torn down automatically when no listeners remain.
      ForumCdcService().unregister(forumId, _cdcListener!);
    }
    channel?.unsubscribe();
    return super.close();
  }
}
