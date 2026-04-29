import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_chat_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_chat_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/widgets/chat_bubble.dart';
import 'package:lynk_x/presentation/features/forum/widgets/message_input.dart';
import 'package:lynk_x/presentation/features/forum/widgets/typing_indicator.dart';
import 'package:lynk_x/presentation/features/forum/widgets/reaction_bar.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';

/// The 'Live Chat' tab content for the Forum.
class LiveChatTab extends StatefulWidget {
  final ScrollController scrollController;
  final String selectedEmoji;
  final int emojiTrigger;
  final VoidCallback onActionTap;
  final Function(String?) onMediaTap;

  const LiveChatTab({
    super.key,
    required this.scrollController,
    required this.selectedEmoji,
    required this.emojiTrigger,
    required this.onActionTap,
    required this.onMediaTap,
  });

  @override
  State<LiveChatTab> createState() => _LiveChatTabState();
}

class _LiveChatTabState extends State<LiveChatTab>
    with AutomaticKeepAliveClientMixin {
  ChatMessage? _reactingToMessage;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(LiveChatTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.emojiTrigger != oldWidget.emojiTrigger && _reactingToMessage != null) {
      _onReactionSelected(widget.selectedEmoji);
    }
  }

  void _onReactionSelected(String emoji) {
    if (_reactingToMessage != null) {
      context.read<ForumCubit>().reactToMessage(_reactingToMessage!, emoji);
      setState(() => _reactingToMessage = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final mainCubit = context.read<ForumCubit>();
    final chatCubit = context.read<ForumChatCubit>();

    return BlocBuilder<ForumCubit, ForumState>(
      buildWhen: (p, c) =>
          p.isOrganizer != c.isOrganizer ||
          p.isMuted != c.isMuted ||
          p.isReadOnly != c.isReadOnly ||
          p.members != c.members,
      builder: (context, mainState) {
        return BlocBuilder<ForumChatCubit, ForumChatState>(
          builder: (context, chatState) {
            return Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: RepaintBoundary(
                        child: RefreshIndicator(
                          onRefresh: () async => chatCubit.refresh(),
                          color: AppColors.primary,
                          child: chatState.messages.isEmpty && !chatState.isLoading
                              ? CustomScrollView(
                                  controller: widget.scrollController,
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  slivers: const [
                                    SliverFillRemaining(
                                      child: Center(
                                        child: EmptyState(message: 'No messages yet. Start the conversation!'),
                                      ),
                                    ),
                                  ],
                                )
                              : CustomScrollView(
                                  controller: widget.scrollController,
                                  reverse: true,
                                  slivers: [
                                    SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                                      sliver: SliverList(
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) {
                                            if (index == chatState.messages.length) {
                                              return const Center(
                                                child: Padding(
                                                  padding: EdgeInsets.all(8.0),
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                                ),
                                              );
                                            }

                                            final message = chatState.messages[index];
                                            
                                            // Grouping logic (compare with older message at index + 1)
                                            bool showSenderInfo = true;
                                            bool isGrouped = false;
                                            if (index < chatState.messages.length - 1) {
                                              final prevMessage = chatState.messages[index + 1];
                                              final timeDiff = message.createdAt.difference(prevMessage.createdAt).abs();
                                              if (message.userId == prevMessage.userId && timeDiff.inMinutes < 5) {
                                                showSenderInfo = false;
                                                isGrouped = true;
                                              }
                                            }

                                            return ChatBubble(
                                              message: message,
                                              showSenderInfo: showSenderInfo,
                                              isGrouped: isGrouped,
                                              onPin: (msg) => mainCubit.pinMessage(msg),
                                              onDelete: (msg) => chatCubit.deleteMessage(msg.id),
                                              onReport: (msg) => chatCubit.reportMessage(msg.id, 'Spam'),
                                              onMute: (msg) => mainCubit.muteUser(msg.userId),
                                              onBan: (msg) => mainCubit.banUser(msg.userId),
                                              onReact: (msg, emoji) => mainCubit.reactToMessage(msg, emoji),
                                              isOrganizer: mainState.isOrganizer,
                                              onReply: (msg) => chatCubit.setReplyTo(msg),
                                              onReactionTap: (msg) => setState(() => _reactingToMessage = msg),
                                              linkPreviewData: chatState.linkPreviews[message.message],
                                              onLinkPreviewDataFetched: (url, data) => chatCubit.saveLinkPreview(url, data),
                                              onMediaTap: widget.onMediaTap,
                                            );
                                          },
                                          childCount: chatState.messages.length + (chatState.isLoading ? 1 : 0),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    if (chatState.isTyping) const TypingIndicator(),
                    MessageInput(
                      onSendMessage: (text, replyTo) => chatCubit.sendMessage(
                        text,
                        isOrganizer: mainState.isOrganizer,
                        isPremium: mainState.isPremium,
                      ),
                      onActionTap: widget.onActionTap,
                      mentionedMedia: chatState.mentionedMedia,
                      onCancelMention: () => chatCubit.setMentionedMedia(null),
                      replyTo: chatState.replyingTo,
                      onCancelReply: () => chatCubit.setReplyTo(null),
                      onChanged: (text) => chatCubit.notifyTyping(),
                      members: mainState.members,
                    ),
                  ],
                ),
                if (_reactingToMessage != null) ...[
                  GestureDetector(
                    onTap: () => setState(() => _reactingToMessage = null),
                    child: Container(
                      color: Colors.black54,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  Positioned(
                    bottom: 100,
                    left: 20,
                    right: 20,
                    child: ReactionBar(
                      onEmojiTap: _onReactionSelected,
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
