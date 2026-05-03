import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_chat_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_chat_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/widgets/message_input.dart';
import 'package:lynk_x/presentation/features/forum/widgets/typing_indicator.dart';
import 'package:lynk_x/presentation/features/forum/widgets/reaction_bar.dart';
import 'package:lynk_x/presentation/features/forum/widgets/chat_message_list.dart';

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
  String? _selectedMessageId;

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
                          color: context.accentColor,
                          child: ChatMessageList(
                            scrollController: widget.scrollController,
                            chatState: chatState,
                            isOrganizer: mainState.isOrganizer,
                            isPremium: mainState.isPremium,
                            onPin: (msg) => mainCubit.pinMessage(msg),
                            onDelete: (msg) => chatCubit.deleteMessage(msg),
                            onReport: (msg) =>
                                chatCubit.reportMessage(msg, 'Spam'),
                            onMute: (msg) => mainCubit.muteUser(msg.userId),
                            onBan: (msg) => mainCubit.banUser(msg.userId),
                            onReact: (msg, emoji) =>
                                mainCubit.reactToMessage(msg, emoji),
                            onReply: (msg) => chatCubit.setReplyTo(msg),
                            onReactionTap: (msg) =>
                                setState(() => _reactingToMessage = msg),
                            onTapBubble: () => setState(() => _selectedMessageId = null),
                            onMessageLongPress: (msg) {
                              setState(() {
                                if (_selectedMessageId == msg.id) {
                                  _selectedMessageId = null;
                                } else {
                                  _selectedMessageId = msg.id;
                                }
                              });
                            },
                            selectedMessageId: _selectedMessageId,
                            onLinkPreviewDataFetched: (String url, LinkPreviewData data) =>
                                chatCubit.saveLinkPreview(url, data),
                            onMediaTap: widget.onMediaTap,
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
                      isReadOnly: mainState.forumStatus == 'read_only',
                      isMuted: mainState.isMuted,
                      isOrganizer: mainState.isOrganizer,
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
