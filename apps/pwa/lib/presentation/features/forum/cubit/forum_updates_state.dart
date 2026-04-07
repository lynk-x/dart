import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'base_message_state.dart';

class ForumUpdatesState extends BaseMessageState {
  final String? selectedCategory;
  final String searchQuery;

  const ForumUpdatesState({
    super.messages = const [],
    super.isLoading = false,
    this.selectedCategory,
    super.mentionedMedia,
    super.linkPreviews = const {},
    this.searchQuery = '',
  });

  ForumUpdatesState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? selectedCategory,
    bool clearCategory = false,
    ForumMedia? mentionedMedia,
    bool clearMentionedMedia = false,
    Map<String, LinkPreviewData>? linkPreviews,
    String? searchQuery,
  }) {
    return ForumUpdatesState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      selectedCategory:
          clearCategory ? null : selectedCategory ?? this.selectedCategory,
      mentionedMedia:
          clearMentionedMedia ? null : mentionedMedia ?? this.mentionedMedia,
      linkPreviews: linkPreviews ?? this.linkPreviews,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        selectedCategory,
        searchQuery,
      ];
}
