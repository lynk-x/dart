import 'package:equatable/equatable.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';

abstract class BaseMessageState extends Equatable {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String searchQuery;
  final ChatMessage? replyingTo;
  final ForumMedia? mentionedMedia;
  final Map<String, LinkPreviewData> linkPreviews;
  final bool showJumpToBottom;

  const BaseMessageState({
    this.messages = const [],
    this.isLoading = false,
    this.searchQuery = '',
    this.replyingTo,
    this.mentionedMedia,
    this.linkPreviews = const {},
    this.showJumpToBottom = false,
  });

  @override
  List<Object?> get props => [
        messages,
        isLoading,
        searchQuery,
        replyingTo,
        mentionedMedia,
        linkPreviews,
        showJumpToBottom,
      ];
}
