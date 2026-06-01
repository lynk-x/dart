import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'base_message_cubit.dart';
import 'forum_updates_state.dart';

class ForumUpdatesCubit extends BaseMessageCubit<ForumUpdatesState> {
  ForumUpdatesCubit({
    required super.forumId,
    required super.userId,
    required super.userName,
    super.channel,
  }) : super(
          messageType: 'announcement',
          initialState: const ForumUpdatesState(),
        );

  @override
  ForumUpdatesState copyWithState({
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
    setupBaseListeners();
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
          .eq('message_type', 'announcement')
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
      final messages =
          data.map((json) => ChatMessage.fromMap(json, userId)).toList();

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
          .eq('message_type', 'announcement')
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

      final more =
          data.map((json) => ChatMessage.fromMap(json, userId)).toList();

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

  void sendMessage(String text,
      {required bool isOrganizer, required bool isPremium}) async {
    if (!isOrganizer) return; // Only organizers send updates
    final messageId = BaseMessageCubit.uuid.v4();
    final now = DateTime.now();
    final mediaId = state.mentionedMedia?.id;
    final imageUrl = state.mentionedMedia?.url;
    final thumbnailUrl = state.mentionedMedia?.thumbnailUrl;

    // Extract #hashtag from text if present, otherwise fall back to selected filter.
    const validHashtags = ['urgent', 'activity', 'Q&A', 'Resources', 'Rules'];
    String? category = state.selectedCategory;
    final hashtagMatch = RegExp(r'#(\w+)', caseSensitive: false).firstMatch(text);
    if (hashtagMatch != null) {
      final tag = hashtagMatch.group(1)!;
      final match = validHashtags.firstWhere(
        (h) => h.toLowerCase() == tag.toLowerCase(),
        orElse: () => '',
      );
      if (match.isNotEmpty) category = match;
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

    try {
      // forum_media is partitioned by created_at; the FK on forum_messages is
      // composite (media_id, media_created_at) — both must be supplied or the
      // FK will not resolve and media will not render in the message.
      final mediaCreatedAt = state.mentionedMedia?.createdAt.toIso8601String();

      await Supabase.instance.client
          .schema('social')
          .from('forum_messages')
          .insert({
        'id': messageId,
        'forum_id': forumId,
        'author_id': userId,
        'content': text,
        'message_type': 'announcement',
        'hashtag': category,
        'created_at': now.toIso8601String(),
        if (mediaId != null) 'media_id': mediaId,
        if (mediaCreatedAt != null) 'media_created_at': mediaCreatedAt,
      });

      // Broadcast
      channel?.sendBroadcastMessage(
        event: 'new_message',
        payload: {
          'id': messageId,
          'author_id': userId,
          'content': text,
          'message_type': 'announcement',
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
          'forum_members': {'role_id': 'organizer'}
        },
      );
      await refresh();
    } catch (e, stack) {
      debugPrint('[ForumUpdatesCubit] Error sending announcement: $e\n$stack');
      await refresh();
    }
  }

  @override
  ForumUpdatesState? fromJson(Map<String, dynamic> json) => ForumUpdatesState.fromMap(json, userId);

  @override
  Map<String, dynamic>? toJson(ForumUpdatesState state) => state.toJson();

  @override
  String get id => forumId;
}
