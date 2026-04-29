import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/services/forum_cache.dart';
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
    final cached =
        await ForumCache.getCachedMessages(forumId, userId, type: 'announcement');
    if (!isClosed) {
      emit(state.copyWith(messages: cached));
    }
    await refresh();
    setupBaseListeners();
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
              '*, user_profile(full_name, is_premium), forum_members!inner(role_id), vw_message_reaction_counts(*)')
          .eq('forum_id', forumId)
          .eq('message_type', 'announcement');

      if (state.selectedCategory != null) {
        query = query.eq('category', state.selectedCategory!);
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
              '*, user_profile(full_name, is_premium), forum_members!inner(role_id), vw_message_reaction_counts(*)')
          .eq('forum_id', forumId)
          .eq('message_type', 'announcement');

      if (state.selectedCategory != null) {
        query = query.eq('category', state.selectedCategory!);
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

    // Detect Category from text if possible, or use current
    String? category = state.selectedCategory;
    if (text.toLowerCase().contains('#general')) category = 'General';
    if (text.toLowerCase().contains('#important')) category = 'Important';
    if (text.toLowerCase().contains('#alert')) category = 'Alert';

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
      await Supabase.instance.client
          .schema('forum_messages')
          .from('forum_messages')
          .insert({
        'id': messageId,
        'forum_id': forumId,
        'author_id': userId,
        'content': text,
        'message_type': 'announcement',
        'category': category,
        if (mediaId != null) 'media_id': mediaId,
      });

      // Broadcast
      channel?.sendBroadcastMessage(
        event: 'new_message',
        payload: {
          'id': messageId,
          'author_id': userId,
          'content': text,
          'message_type': 'announcement',
          'category': category,
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
}
