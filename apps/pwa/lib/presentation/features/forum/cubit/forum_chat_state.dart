import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'base_message_state.dart';

class ForumChatState extends BaseMessageState {
  final ChatMessage? replyingTo;
  final bool isTyping;
  final bool showJumpToBottom;
  final String? error;
  final String searchQuery;

  const ForumChatState({
    super.messages = const [],
    super.isLoading = false,
    this.replyingTo,
    super.mentionedMedia,
    this.isTyping = false,
    this.showJumpToBottom = false,
    super.linkPreviews = const {},
    this.error,
    this.searchQuery = '',
  });

  ForumChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    ChatMessage? replyingTo,
    bool clearReplyTo = false,
    ForumMedia? mentionedMedia,
    bool clearMentionedMedia = false,
    bool? isTyping,
    bool? showJumpToBottom,
    Map<String, LinkPreviewData>? linkPreviews,
    String? error,
    bool clearError = false,
    String? searchQuery,
  }) {
    return ForumChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      replyingTo: clearReplyTo ? null : replyingTo ?? this.replyingTo,
      mentionedMedia:
          clearMentionedMedia ? null : mentionedMedia ?? this.mentionedMedia,
      isTyping: isTyping ?? this.isTyping,
      showJumpToBottom: showJumpToBottom ?? this.showJumpToBottom,
      linkPreviews: linkPreviews ?? this.linkPreviews,
      error: clearError ? null : error ?? this.error,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        replyingTo,
        isTyping,
        showJumpToBottom,
        error,
        searchQuery,
      ];
}
