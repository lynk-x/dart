import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/widgets/chat_bubble.dart';
import 'package:lynk_x/presentation/features/forum/widgets/forum_skeletons.dart';
import 'package:lynk_x/presentation/features/forum/widgets/swipe_to_reply.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/base_message_state.dart';

final _urlRegExp = RegExp(r'(?:(?:https?|ftp)://)?[\w/\-?=%.]+\.[\w/\-?=%.]+');

LinkPreviewData? _linkPreviewFor(
    String messageText, Map<String, LinkPreviewData> previews) {
  final match = _urlRegExp.firstMatch(messageText);
  if (match == null) return null;
  final raw = messageText.substring(match.start, match.end);
  final url = raw.startsWith('http') ? raw : 'https://$raw';
  return previews[url];
}

/// A specialized widget to render the list of chat messages in the forum.
/// Handles grouping logic and infinite scroll loading indicators.
class ChatMessageList extends StatelessWidget {
  final ScrollController scrollController;
  final BaseMessageState chatState;
  final bool isOrganizer;
  final bool isPremium;
  final Function(ChatMessage)? onPin;
  final Function(ChatMessage)? onDelete;
  final Function(ChatMessage)? onEdit;
  final Function(ChatMessage)? onReport;
  final Function(ChatMessage)? onMute;
  final Function(ChatMessage)? onBan;
  final Function(ChatMessage)? onReply;
  final VoidCallback? onLongPressBubble;
  final String? selectedMessageId;
  final Function(ChatMessage)? onMessageLongPress;
  final Function(String, LinkPreviewData)? onLinkPreviewDataFetched;
  final Function(String?)? onMediaTap;
  final VoidCallback? onTapBubble;
  final double topPadding;

  const ChatMessageList({
    super.key,
    required this.scrollController,
    required this.chatState,
    required this.isOrganizer,
    required this.isPremium,
    this.onPin,
    this.onDelete,
    this.onEdit,
    this.onReport,
    this.onMute,
    this.onBan,
    this.onReply,
    this.onLongPressBubble,
    this.selectedMessageId,
    this.onMessageLongPress,
    this.onLinkPreviewDataFetched,
    this.onMediaTap,
    this.onTapBubble,
    this.topPadding = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (chatState.messages.isEmpty && !chatState.isLoading) {
      return CustomScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: const [
          SliverFillRemaining(
            child: Center(
              child: EmptyState(
                  message: 'No messages yet. Start the conversation!'),
            ),
          ),
        ],
      );
    }

    if (chatState.messages.isEmpty && chatState.isLoading) {
      // Skeleton bubbles rather than a bare spinner — the eventual content
      // is a list of chat bubbles, so preview that shape directly.
      return const SkeletonChatBubbleList();
    }

    return CustomScrollView(
      controller: scrollController,
      reverse: true,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 16 + topPadding, 16, 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index == chatState.messages.length) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: context.accentColor),
                    ),
                  );
                }

                final message = chatState.messages[index];

                // Grouping logic (compare with older message at index + 1)
                bool showSenderInfo = true;
                bool isGrouped = false;
                if (index < chatState.messages.length - 1) {
                  final prevMessage = chatState.messages[index + 1];
                  final timeDiff =
                      message.createdAt.difference(prevMessage.createdAt).abs();
                  if (message.userId == prevMessage.userId &&
                      timeDiff.inMinutes < 5) {
                    showSenderInfo = false;
                    isGrouped = true;
                  }
                }

                final bubble = ChatBubble(
                  message: message,
                  showSenderInfo: showSenderInfo,
                  isGrouped: isGrouped,
                  onPin: onPin,
                  onDelete: onDelete,
                  onEdit: onEdit,
                  onReport: onReport,
                  onMute: onMute,
                  onBan: onBan,
                  isOrganizer: isOrganizer,
                  onReply: onReply,
                  onTapBubble: onTapBubble,
                  onLongPressBubble: onLongPressBubble ??
                      () => onMessageLongPress?.call(message),
                  showActions: selectedMessageId == message.id,
                  linkPreviewData:
                      _linkPreviewFor(message.message, chatState.linkPreviews),
                  onLinkPreviewDataFetched: onLinkPreviewDataFetched,
                  onMediaTap: onMediaTap,
                );

                if (onReply != null) {
                  return SwipeToReply(
                    onReply: () => onReply!.call(message),
                    child: bubble,
                  );
                }

                return bubble;
              },
              childCount: chatState.messages.isNotEmpty
                  ? chatState.messages.length + (chatState.isLoading ? 1 : 0)
                  : 0,
            ),
          ),
        ),
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
      ],
    );
  }
}
