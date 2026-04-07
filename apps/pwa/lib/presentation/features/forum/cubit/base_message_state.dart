import 'package:equatable/equatable.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';

abstract class BaseMessageState extends Equatable {
  final List<ChatMessage> messages;
  final bool isLoading;
  final ForumMedia? mentionedMedia;
  final Map<String, LinkPreviewData> linkPreviews;

  const BaseMessageState({
    this.messages = const [],
    this.isLoading = false,
    this.mentionedMedia,
    this.linkPreviews = const {},
  });

  @override
  List<Object?> get props => [
        messages,
        isLoading,
        mentionedMedia,
        linkPreviews,
      ];
}
