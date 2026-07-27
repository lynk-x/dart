import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_state.dart';
import 'package:lynk_x/presentation/features/forum/widgets/message_input.dart';
import 'package:lynk_x/presentation/features/forum/widgets/chat_bubble.dart';
import 'package:lynk_x/presentation/features/forum/widgets/forum_skeletons.dart';
import 'package:lynk_x/presentation/features/forum/widgets/swipe_to_reply.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';

/// The 'Updates' tab content for the Forum.
class UpdatesTab extends StatefulWidget {
  final ScrollController scrollController;
  final VoidCallback onActionTap;
  final Function(String?) onMediaTap;
  final VoidCallback? onCreatePollOrQuiz;

  const UpdatesTab({
    super.key,
    required this.scrollController,
    required this.onActionTap,
    required this.onMediaTap,
    this.onCreatePollOrQuiz,
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
  void didUpdateWidget(covariant UpdatesTab oldWidget) {
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
      context.read<ForumUpdatesCubit>().loadMore();
    }
  }

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
                      child: SkeletonFadeSingleMount(
                        child: updatesState.messages.isEmpty &&
                                updatesState.isLoading
                            ? _SkeletonScrollView(
                                key: const ValueKey('skeleton'),
                                scrollController: widget.scrollController,
                              )
                            : _UpdatesScrollView(
                                key: ValueKey(updatesCubit.hasCompletedInitialRefresh
                                    ? 'content'
                                    : 'content-pending'),
                                scrollController: widget.scrollController,
                                updatesState: updatesState,
                                mainCubit: mainCubit,
                                updatesCubit: updatesCubit,
                                mainState: mainState,
                                selectedMessageId: _selectedMessageId,
                                onMediaTap: widget.onMediaTap,
                                onSelectMessage: (id) =>
                                    setState(() => _selectedMessageId = id),
                              ),
                      ),
                    ),
                  ),
                ),
                if (mainState.isOrganizer)
                  MessageInput(
                    onSendMessage: (text, _) {
                      if (updatesState.editingMessage != null) {
                        updatesCubit.editMessage(
                            updatesState.editingMessage!, text);
                        updatesCubit.setEditingMessage(null);
                      } else {
                        updatesCubit.sendMessage(
                          text,
                          isOrganizer: mainState.isOrganizer,
                          isPremium: mainState.isPremium,
                        );
                      }
                    },
                    onActionTap: widget.onActionTap,
                    onCreatePollOrQuiz: widget.onCreatePollOrQuiz,
                    mentionedMedia: updatesState.mentionedMedia,
                    onCancelMention: () => updatesCubit.setMentionedMedia(null),
                    editingMessage: updatesState.editingMessage,
                    onCancelEdit: () => updatesCubit.setEditingMessage(null),
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

/// Extracted so [SkeletonFade] can crossfade between this and the skeleton
/// as a single, independently-keyed subtree (AnimatedSwitcher needs its
/// child to be one widget, not a sliver list spliced into an outer
/// CustomScrollView).
class _UpdatesScrollView extends StatelessWidget {
  final ScrollController scrollController;
  final ForumUpdatesState updatesState;
  final ForumCubit mainCubit;
  final ForumUpdatesCubit updatesCubit;
  final ForumState mainState;
  final String? selectedMessageId;
  final Function(String?) onMediaTap;
  final ValueChanged<String?> onSelectMessage;

  const _UpdatesScrollView({
    super.key,
    required this.scrollController,
    required this.updatesState,
    required this.mainCubit,
    required this.updatesCubit,
    required this.mainState,
    required this.selectedMessageId,
    required this.onMediaTap,
    required this.onSelectMessage,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      reverse: true,
      slivers: [
        // Unconditional — forum_screen.dart's NestedScrollView header always
        // has exactly one SliverOverlapAbsorber expecting exactly one
        // injector to consume its handle each frame. Gating this on
        // messages.isNotEmpty left the empty/loading state with zero
        // injectors while the absorber above still expected one, which
        // threw (surfaced as an opaque minified exception + a blank grey
        // content area) on every fresh forum open, before the first
        // message page had loaded.
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        if (updatesState.messages.isEmpty && !updatesState.isLoading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              message: 'No messages yet. Start the conversation!',
            ),
          ),
        if (updatesState.messages.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == updatesState.messages.length) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: context.accentColor),
                      ),
                    );
                  }

                  final message = updatesState.messages[index];
                  final bubble = ChatBubble(
                    message: message,
                    isOrganizer: mainState.isOrganizer,
                    onPin: (msg) => mainCubit.pinMessage(msg),
                    onDelete: (msg) => updatesCubit.deleteMessage(msg),
                    onEdit: (msg) => updatesCubit.setEditingMessage(msg),
                    onReport: (msg) => updatesCubit.reportMessage(msg, 'Spam'),
                    onMute: (msg) => mainCubit.muteUser(msg.userId),
                    onBan: (msg) => mainCubit.banUser(msg.userId),
                    onReply: (msg) => updatesCubit.setReplyTo(msg),
                    onMediaTap: onMediaTap,
                    showActions: selectedMessageId == message.id,
                    onLongPressBubble: () {
                      onSelectMessage(
                          selectedMessageId == message.id ? null : message.id);
                    },
                    onTapBubble: () => onSelectMessage(null),
                  );

                  // Mirrors chat_message_list.dart's Live Chat wrapping —
                  // without this, mobile has no touch-reachable reply
                  // trigger at all (the reply icon in ChatBubble is
                  // desktop-only), for any message type.
                  return SwipeToReply(
                    onReply: () => updatesCubit.setReplyTo(message),
                    child: bubble,
                  );
                },
                childCount: updatesState.messages.isNotEmpty
                    ? updatesState.messages.length +
                        (updatesState.isLoading ? 1 : 0)
                    : 0,
              ),
            ),
          ),
      ],
    );
  }
}

/// Skeleton-state counterpart to [_UpdatesScrollView] — needs its own
/// SliverOverlapInjector for the same reason: forum_screen.dart's
/// NestedScrollView header always expects exactly one injector consuming
/// its SliverOverlapAbsorber handle each frame, regardless of whether this
/// tab currently has any messages loaded.
class _SkeletonScrollView extends StatelessWidget {
  final ScrollController scrollController;

  const _SkeletonScrollView({super.key, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      reverse: true,
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        const SliverFillRemaining(
          hasScrollBody: false,
          child: SkeletonChatBubbleList(),
        ),
      ],
    );
  }
}
