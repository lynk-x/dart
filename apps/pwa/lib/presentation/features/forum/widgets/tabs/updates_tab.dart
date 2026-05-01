import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_state.dart';
import 'package:lynk_x/presentation/features/forum/widgets/info_banner.dart';
import 'package:lynk_x/presentation/features/forum/widgets/message_input.dart';
import 'package:lynk_x/presentation/features/forum/widgets/chat_bubble.dart';
import 'package:lynk_x/presentation/features/forum/widgets/category_filter_bar.dart';

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
            final pinned = updatesState.messages.where((m) => m.isPinned).toList();
            final hasPinned = pinned.isNotEmpty;
            
            return Column(
              children: [
                Expanded(
                  child: RepaintBoundary(
                    child: RefreshIndicator(
                      onRefresh: () async => updatesCubit.refresh(),
                      color: AppColors.primary,
                      child: CustomScrollView(
                        controller: widget.scrollController,
                        reverse: true,
                        slivers: [
                          // 1. Bottom Padding (for reverse: true)
                          const SliverToBoxAdapter(child: SizedBox(height: 16)),

                          // 2. Messages List
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  if (index == updatesState.messages.length) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: AppColors.primary),
                                      ),
                                    );
                                  }

                                  final message = updatesState.messages[index];
                                  return ChatBubble(
                                    message: message,
                                    isOrganizer: mainState.isOrganizer,
                                    onPin: (msg) => mainCubit.pinMessage(msg),
                                    onDelete: (msg) => updatesCubit.deleteMessage(msg.id),
                                    onReport: (msg) => updatesCubit.reportMessage(msg.id, 'Spam'),
                                    onMute: (msg) => mainCubit.muteUser(msg.userId),
                                    onBan: (msg) => mainCubit.banUser(msg.userId),
                                    onReact: (msg, emoji) => mainCubit.reactToMessage(msg, emoji),
                                    onReply: (msg) => updatesCubit.setReplyTo(msg),
                                    onMediaTap: widget.onMediaTap,
                                    showActions: _selectedMessageId == message.id,
                                    onLongPressBubble: () {
                                      setState(() {
                                        if (_selectedMessageId == message.id) {
                                          _selectedMessageId = null;
                                        } else {
                                          _selectedMessageId = message.id;
                                        }
                                      });
                                    },
                                    onTapBubble: () => setState(() => _selectedMessageId = null),
                                  );
                                },
                                childCount: updatesState.messages.length + (updatesState.isLoading ? 1 : 0),
                              ),
                            ),
                          ),

                          // 3. Pinned Info Banner (below filter)
                          if (hasPinned)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: InfoBanner(
                                  icon: Icons.push_pin,
                                  text: pinned.first.message.length > 80
                                      ? '${pinned.first.message.substring(0, 80)}…'
                                      : pinned.first.message,
                                ),
                              ),
                            ),
                          
                          // 4. Pinned Category Filter (Absolute Top)
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _PinnedHeaderDelegate(
                              height: 60,
                              child: Container(
                                color: AppColors.primaryBackground,
                                alignment: Alignment.bottomCenter,
                                padding: const EdgeInsets.only(bottom: 8),
                                child: CategoryFilterBar(
                                  selectedCategory: updatesState.selectedCategory,
                                  onSelectionChanged: (cat) => updatesCubit.setCategory(cat),
                                ),
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
                    onCancelMention: () => updatesCubit.setMentionedMedia(null),
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

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _PinnedHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return height != oldDelegate.height || child != oldDelegate.child;
  }
}
