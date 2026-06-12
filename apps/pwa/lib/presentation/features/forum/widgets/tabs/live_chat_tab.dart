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
  String? _selectedMessageId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LiveChatTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
  }

  void _onScroll() {
    if (!mounted) return;
    if (!widget.scrollController.hasClients) return;
    final maxScroll = widget.scrollController.position.maxScrollExtent;
    final currentScroll = widget.scrollController.position.pixels;
    if (maxScroll - currentScroll <= 200) {
      context.read<ForumChatCubit>().loadMore();
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
        return Column(
          children: [
            Expanded(
              child: RepaintBoundary(
                child: RefreshIndicator(
                  onRefresh: () async => chatCubit.refresh(),
                  color: context.accentColor,
                  child: BlocBuilder<ForumChatCubit, ForumChatState>(
                    buildWhen: (p, c) =>
                        p.messages != c.messages ||
                        p.isLoading != c.isLoading ||
                        p.linkPreviews != c.linkPreviews,
                    builder: (context, chatState) {
                      return ChatMessageList(
                        scrollController: widget.scrollController,
                        chatState: chatState,
                        isOrganizer: mainState.isOrganizer,
                        isPremium: mainState.isPremium,
                        onPin: (msg) => mainCubit.pinMessage(msg),
                        onDelete: (msg) => chatCubit.deleteMessage(msg),
                        onEdit: (msg) => chatCubit.setEditingMessage(msg),
                        onReport: (msg) =>
                            chatCubit.reportMessage(msg, 'Spam'),
                        onMute: (msg) => mainCubit.muteUser(msg.userId),
                        onBan: (msg) => mainCubit.banUser(msg.userId),
                        onReply: (msg) => chatCubit.setReplyTo(msg),
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
                      );
                    },
                  ),
                ),
              ),
            ),
            BlocSelector<ForumChatCubit, ForumChatState, bool>(
              selector: (state) => state.isTyping,
              builder: (context, isTyping) {
                return isTyping ? const TypingIndicator() : const SizedBox.shrink();
              },
            ),
            BlocBuilder<ForumChatCubit, ForumChatState>(
              buildWhen: (p, c) =>
                  p.editingMessage != c.editingMessage ||
                  p.replyingTo != c.replyingTo ||
                  p.mentionedMedia != c.mentionedMedia,
              builder: (context, chatState) {
                return MessageInput(
                  onSendMessage: (text, replyTo) {
                    if (chatState.editingMessage != null) {
                      chatCubit.editMessage(chatState.editingMessage!, text);
                      chatCubit.setEditingMessage(null);
                    } else {
                      chatCubit.sendMessage(
                        text,
                        isOrganizer: mainState.isOrganizer,
                        isPremium: mainState.isPremium,
                      );
                    }
                  },
                  onActionTap: widget.onActionTap,
                  mentionedMedia: chatState.mentionedMedia,
                  onCancelMention: () => chatCubit.setMentionedMedia(null),
                  replyTo: chatState.replyingTo,
                  onCancelReply: () => chatCubit.setReplyTo(null),
                  editingMessage: chatState.editingMessage,
                  onCancelEdit: () => chatCubit.setEditingMessage(null),
                  onChanged: (text) => chatCubit.notifyTyping(),
                  members: mainState.members,
                  isReadOnly: mainState.forumStatus == 'read_only',
                  isMuted: mainState.isMuted,
                  isOrganizer: mainState.isOrganizer,
                );
              },
            ),
          ],
        );
      },
    );
  }
}
