import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_state.dart';
import 'package:lynk_x/presentation/features/forum/widgets/message_input.dart';
import 'package:lynk_x/presentation/features/forum/widgets/chat_bubble.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';

/// The 'Updates' tab content for the Forum.
class UpdatesTab extends StatefulWidget {
  final ScrollController scrollController;
  final VoidCallback onActionTap;
  final Function(String?) onMediaTap;

  const UpdatesTab({
    super.key,
    required this.scrollController,
    required this.onActionTap,
    required this.onMediaTap,
  });

  @override
  State<UpdatesTab> createState() => _UpdatesTabState();
}

class _UpdatesTabState extends State<UpdatesTab>
    with AutomaticKeepAliveClientMixin {
  String? _selectedMessageId;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final mainCubit = context.read<ForumCubit>();
    final updatesCubit = context.read<ForumUpdatesCubit>();

    return BlocBuilder<ForumCubit, ForumState>(
      buildWhen: (p, c) =>
          p.isOrganizer != c.isOrganizer ||
          p.isMuted != c.isMuted ||
          p.isReadOnly != c.isReadOnly ||
          p.members != c.members,
      builder: (context, mainState) {
        return BlocBuilder<ForumUpdatesCubit, ForumUpdatesState>(
          builder: (context, updatesState) {
            return Column(
              children: [
                Expanded(
                  child: RepaintBoundary(
                    child: RefreshIndicator(
                      onRefresh: () async => updatesCubit.refresh(),
                      color: context.accentColor,
                      child: CustomScrollView(
                        controller: widget.scrollController,
                        reverse: true,
                        slivers: [
                          // Empty state
                          if (updatesState.messages.isEmpty && !updatesState.isLoading)
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: EmptyState(
                                message: 'No messages yet. Start the conversation!',
                              ),
                            ),

                          // Messages
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  if (index ==
                                      updatesState.messages.length) {
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: context.accentColor),
                                      ),
                                    );
                                  }

                                  final message =
                                      updatesState.messages[index];
                                  return ChatBubble(
                                    message: message,
                                    isOrganizer: mainState.isOrganizer,
                                    onPin: (msg) =>
                                        mainCubit.pinMessage(msg),
                                    onDelete: (msg) =>
                                        updatesCubit.deleteMessage(msg),
                                    onReport: (msg) =>
                                        updatesCubit.reportMessage(msg, 'Spam'),
                                    onMute: (msg) =>
                                        mainCubit.muteUser(msg.userId),
                                    onBan: (msg) =>
                                        mainCubit.banUser(msg.userId),
                                    onReact: (msg, emoji) =>
                                        mainCubit.reactToMessage(
                                            msg, emoji),
                                    onReply: (msg) =>
                                        updatesCubit.setReplyTo(msg),
                                    onMediaTap: widget.onMediaTap,
                                    showActions:
                                        _selectedMessageId == message.id,
                                    onLongPressBubble: () {
                                      setState(() {
                                        _selectedMessageId =
                                            _selectedMessageId == message.id
                                                ? null
                                                : message.id;
                                      });
                                    },
                                    onTapBubble: () => setState(
                                        () => _selectedMessageId = null),
                                  );
                                },
                                childCount: updatesState.messages.length +
                                    (updatesState.isLoading ? 1 : 0),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (mainState.isOrganizer)
                  MessageInput(
                    onSendMessage: (text, _) => updatesCubit.sendMessage(
                      text,
                      isOrganizer: mainState.isOrganizer,
                      isPremium: mainState.isPremium,
                    ),
                    onActionTap: widget.onActionTap,
                    mentionedMedia: updatesState.mentionedMedia,
                    onCancelMention: () =>
                        updatesCubit.setMentionedMedia(null),
                    onChanged: (text) {},
                    members: mainState.members,
                    isOrganizer: true,
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
