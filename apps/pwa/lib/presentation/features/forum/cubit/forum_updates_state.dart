import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'base_message_state.dart';

class ForumUpdatesState extends BaseMessageState {
  final String? selectedCategory;

  const ForumUpdatesState({
    super.messages,
    super.isLoading,
    super.searchQuery,
    super.replyingTo,
    super.mentionedMedia,
    super.linkPreviews,
    super.showJumpToBottom,
    this.selectedCategory,
  });

  ForumUpdatesState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? searchQuery,
    ChatMessage? replyingTo,
    bool clearReplyTo = false,
    String? selectedCategory,
    bool clearCategory = false,
    ForumMedia? mentionedMedia,
    bool clearMentionedMedia = false,
    Map<String, LinkPreviewData>? linkPreviews,
    bool? showJumpToBottom,
  }) {
    return ForumUpdatesState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
      replyingTo: clearReplyTo ? null : replyingTo ?? this.replyingTo,
      mentionedMedia:
          clearMentionedMedia ? null : mentionedMedia ?? this.mentionedMedia,
      linkPreviews: linkPreviews ?? this.linkPreviews,
      showJumpToBottom: showJumpToBottom ?? this.showJumpToBottom,
      selectedCategory:
          clearCategory ? null : selectedCategory ?? this.selectedCategory,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        selectedCategory,
      ];

  Map<String, dynamic> toJson() => {
        ...baseToMap(),
        'selectedCategory': selectedCategory,
      };

  static ForumUpdatesState fromMap(Map<String, dynamic> map) {
    return ForumUpdatesState(
      messages: (map['messages'] as List? ?? [])
          .map((m) => ChatMessage.fromMap(m as Map<String, dynamic>, ''))
          .toList(),
      searchQuery: map['searchQuery'] as String? ?? '',
      selectedCategory: map['selectedCategory'] as String?,
      linkPreviews: (map['linkPreviews'] as Map? ?? {}).map(
        (k, v) => MapEntry(
          k as String,
          LinkPreviewData.fromMap(v as Map<String, dynamic>),
        ),
      ),
    );
  }
}
