import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_state.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/widgets/chat_bubble.dart';
import 'package:lynk_x/presentation/features/forum/widgets/info_banner.dart';
import 'package:lynk_x/presentation/features/forum/widgets/message_input.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';
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
  ChatMessage? _selectedMessage;

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
            
            return Column(
              children: [
                if (pinned.isNotEmpty) ...[
                  InfoBanner(
                    icon: Icons.push_pin,
                    text: pinned.first.message.length > 80
                        ? '${pinned.first.message.substring(0, 80)}…'
                        : pinned.first.message,
                  ),
                  const SizedBox(height: 8),
                ],
                CategoryFilterBar(
                  selectedCategory: updatesState.selectedCategory,
                  onSelectionChanged: (cat) => updatesCubit.setCategory(cat),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: RepaintBoundary(
                    child: RefreshIndicator(
                      onRefresh: () async => updatesCubit.refresh(),
                      color: AppColors.primary,
                      child: updatesState.messages.isEmpty && !updatesState.isLoading
                          ? CustomScrollView(
                              controller: widget.scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: const [
                                SliverFillRemaining(
                                  child: Center(
                                    child: EmptyState(message: 'No updates yet'),
                                  ),
                                ),
                              ],
                            )
                          : CustomScrollView(
                              controller: widget.scrollController,
                              reverse: true,
                              slivers: [
                                SliverPadding(
                                  padding: const EdgeInsets.all(16),
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
                                          onPin: (msg) => mainCubit.pinMessage(msg),
                                          onDelete: (msg) => updatesCubit.deleteMessage(msg.id),
                                          onReport: (msg) => updatesCubit.reportMessage(msg.id, 'Spam'),
                                          onMute: (msg) => mainCubit.muteUser(msg.userId),
                                          onBan: (msg) => mainCubit.banUser(msg.userId),
                                          onReact: (msg, emoji) => mainCubit.reactToMessage(msg, emoji),
                                          isOrganizer: mainState.isOrganizer,
                                          onReply: (msg) => updatesCubit.setReplyTo(msg),
                                          onLongPressBubble: () {
                                            setState(() {
                                              if (_selectedMessage == message) {
                                                _selectedMessage = null;
                                              } else {
                                                _selectedMessage = message;
                                              }
                                            });
                                          },
                                          showActions: _selectedMessage == message,
                                          linkPreviewData: updatesState.linkPreviews[message.message],
                                          onLinkPreviewDataFetched: (url, data) => updatesCubit.saveLinkPreview(url, data),
                                          onMediaTap: widget.onMediaTap,
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
                MessageInput(
                  onSendMessage: (text, replyTo) => updatesCubit.sendMessage(
                    text,
                    isOrganizer: mainState.isOrganizer,
                    isPremium: mainState.isPremium,
                  ),
                  onActionTap: widget.onActionTap,
                  mentionedMedia: updatesState.mentionedMedia,
                  onCancelMention: () => updatesCubit.setMentionedMedia(null),
                  onChanged: (text) {},
                  members: mainState.members,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
