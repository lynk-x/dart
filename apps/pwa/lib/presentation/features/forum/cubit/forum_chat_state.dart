import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'base_message_state.dart';

class ForumChatState extends BaseMessageState {
  final bool isTyping;
  final String? error;

  const ForumChatState({
    super.messages,
    super.isLoading,
    super.searchQuery,
    super.replyingTo,
    super.editingMessage,
    super.mentionedMedia,
    super.linkPreviews,
    super.showJumpToBottom,
    this.isTyping = false,
    this.error,
  });

  ForumChatState copyWith({
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
    bool? isTyping,
    String? error,
    bool clearError = false,
  }) {
    return ForumChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
      replyingTo: clearReplyTo ? null : replyingTo ?? this.replyingTo,
      editingMessage:
          clearEditingMessage ? null : editingMessage ?? this.editingMessage,
      mentionedMedia:
          clearMentionedMedia ? null : mentionedMedia ?? this.mentionedMedia,
      linkPreviews: linkPreviews ?? this.linkPreviews,
      showJumpToBottom: showJumpToBottom ?? this.showJumpToBottom,
      isTyping: isTyping ?? this.isTyping,
      error: clearError ? null : error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        isTyping,
        error,
      ];

  Map<String, dynamic> toJson() => baseToMap();

  static ForumChatState fromMap(Map<String, dynamic> map, [String userId = '']) {
    return ForumChatState(
      messages: (map['messages'] as List? ?? [])
          .map((m) => ChatMessage.fromMap(m as Map<String, dynamic>, userId))
          .toList(),
      searchQuery: map['searchQuery'] as String? ?? '',
      linkPreviews: (map['linkPreviews'] as Map? ?? {}).map(
        (k, v) => MapEntry(
          k as String,
          LinkPreviewData.fromMap(v as Map<String, dynamic>),
        ),
      ),
    );
  }
}
