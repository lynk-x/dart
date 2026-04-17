import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_chat_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/widgets/chat_bubble.dart';
import 'package:lynk_x/presentation/features/forum/widgets/info_banner.dart';
import 'package:lynk_x/presentation/features/forum/widgets/message_input.dart';
import 'package:lynk_x/presentation/features/forum/widgets/reaction_background.dart';
import 'package:lynk_x/presentation/features/forum/widgets/typing_indicator.dart';
import 'package:lynk_x/presentation/features/forum/widgets/reaction_bar.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';

/// The 'Live Chat' tab content for the Forum.
class LiveChatTab extends StatefulWidget {
  final ScrollController scrollController;
  final bool isOrganizer;
  final bool isMuted;
  final String selectedEmoji;
  final int emojiTrigger;
  final List<Map<String, dynamic>> members;

  // External actions
  final Function(ChatMessage, String)? onReact;
  final Function(ChatMessage)? onPin;
  final Function(ChatMessage)? onReport;
  final Function(ChatMessage)? onMute;
  final Function(ChatMessage)? onBan;
  final Function(String?) onMediaTap;
  final VoidCallback onActionTap;

  const LiveChatTab({
    super.key,
    required this.scrollController,
    this.isOrganizer = false,
    this.isMuted = false,
    required this.selectedEmoji,
    required this.emojiTrigger,
    this.members = const [],
    this.onReact,
    this.onPin,
    this.onReport,
    this.onMute,
    this.onBan,
    required this.onMediaTap,
    required this.onActionTap,
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
  Widget build(BuildContext context) {
    super.build(context);
    final chatCubit = context.watch<ForumChatCubit>();
    final chatState = chatCubit.state;

    return Column(
      children: [
        const InfoBanner(
          icon: Icons.info,
          text: 'Active/Live Chat',
        ),
        const SizedBox(height: 12),
        if (_reactingToMessage != null &&
            context.read<FeatureFlagCubit>().isEnabled('enable_forum_reactions'))
          ReactionBar(
            onEmojiTap: (emoji) {
              if (widget.onReact != null) {
                widget.onReact!(_reactingToMessage!, emoji);
              }
              setState(() {
                _reactingToMessage = null;
              });
            },
          ),
        Expanded(
          child: RepaintBoundary(
            child: Stack(
              children: [
                RefreshIndicator(
                  onRefresh: chatCubit.refresh,
                  color: AppColors.primary,
                  child: chatState.messages.isEmpty && !chatState.isLoading
                      ? ListView(
                          controller: widget.scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 100),
                            EmptyState(message: 'No messages yet'),
                          ],
                        )
                      : ListView.builder(
                          controller: widget.scrollController,
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: chatState.messages.length +
                              (chatState.isLoading ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == chatState.messages.length) {
                              return _buildLoader();
                            }
                            final msg = chatState.messages[index];
                            return ChatBubble(
                              message: msg,
                              onReply: chatCubit.setReplyTo,
                              onReact: widget.onReact,
                              onMediaTap: () => widget.onMediaTap(msg.imageUrl),
                              onPin: widget.onPin,
                              onReport: widget.onReport,
                              onMute: widget.onMute,
                              onBan: widget.onBan,
                              isOrganizer: widget.isOrganizer,
                              showActions: msg == _reactingToMessage,
                              onLongPressBubble: () {
                                setState(() {
                                  if (_reactingToMessage == msg) {
                                    _reactingToMessage = null;
                                  } else {
                                    _reactingToMessage = msg;
                                  }
                                });
                              },
                              linkPreviewData:
                                  chatState.linkPreviews[msg.message],
                              onLinkPreviewDataFetched:
                                  chatCubit.saveLinkPreview,
                            );
                          },
                        ),
                ),
                if (chatState.showJumpToBottom)
                  _buildJumpToBottomButton(() {
                    widget.scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOut,
                    );
                  }),
                if (context.read<FeatureFlagCubit>().isEnabled('enable_forum_reactions'))
                  IgnorePointer(
                    child: ReactionBackground(
                      emoji: widget.selectedEmoji,
                      trigger: widget.emojiTrigger,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (chatState.isTyping) const TypingIndicator(),
        if (!widget.isMuted)
          MessageInput(
            replyTo: chatState.replyingTo,
            onCancelReply: () => chatCubit.setReplyTo(null),
            onSendMessage: (text, replyTo) {
              chatCubit.sendMessage(text, 
                isOrganizer: widget.isOrganizer,
                isPremium: context.read<ForumCubit>().state.isPremium,
              );
            },
            onActionTap: widget.onActionTap,
            mentionedMedia: chatState.mentionedMedia,
            onCancelMention: () => chatCubit.setMentionedMedia(null),
            onChanged: (text) {
              if (text.isNotEmpty) {
                chatCubit.notifyTyping();
              }
            },
            members: widget.members,
          ),
      ],
    );
  }

  Widget _buildJumpToBottomButton(VoidCallback onTap) {
    return Positioned(
      bottom: 20,
      right: 20,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10)],
          ),
          child: const Icon(Icons.arrow_downward,
              color: AppColors.secondaryText, size: 24),
        ),
      ),
    );
  }

  Widget _buildLoader() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(8.0),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
