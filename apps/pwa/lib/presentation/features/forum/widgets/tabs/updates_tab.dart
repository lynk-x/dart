import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/widgets/chat_bubble.dart';
import 'package:lynk_x/presentation/features/forum/widgets/info_banner.dart';
import 'package:lynk_x/presentation/features/forum/widgets/message_input.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';
import 'package:lynk_x/presentation/features/forum/widgets/category_filter_bar.dart';

/// The 'Updates' tab content for the Forum.
class UpdatesTab extends StatefulWidget {
  final List<ChatMessage> messages;
  final ScrollController scrollController;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final Function(String, ChatMessage?) onSendMessage;
  final Function(ChatMessage)? onPin;
  final Function(ChatMessage)? onDelete;
  final Function(ChatMessage)? onReport;
  final Function(ChatMessage)? onMute;
  final Function(ChatMessage)? onBan;
  final Function(ChatMessage, String)? onReact;
  final String? selectedCategory;
  final Function(String?) onSelectionChanged;
  final VoidCallback onActionTap;
  final bool isOrganizer;
  final ForumMedia? mentionedMedia;
  final VoidCallback? onCancelMention;
  final List<Map<String, dynamic>> members;
  final Map<String, LinkPreviewData> linkPreviews;
  final Function(String, LinkPreviewData) onLinkPreviewDataFetched;

  const UpdatesTab({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.isLoading,
    required this.onRefresh,
    required this.onSendMessage,
    this.onPin,
    this.onDelete,
    this.onReport,
    this.onMute,
    this.onBan,
    this.onReact,
    required this.selectedCategory,
    required this.onSelectionChanged,
    required this.onActionTap,
    this.isOrganizer = false,
    this.mentionedMedia,
    this.onCancelMention,
    this.members = const [],
    this.linkPreviews = const {},
    required this.onLinkPreviewDataFetched,
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
    return Column(
      children: [
        Builder(
          builder: (_) {
            final pinned = widget.messages.where((m) => m.isPinned).toList();
            if (pinned.isEmpty) return const SizedBox.shrink();
            final preview = pinned.first.message.length > 80
                ? '${pinned.first.message.substring(0, 80)}…'
                : pinned.first.message;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InfoBanner(icon: Icons.push_pin, text: preview),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
        CategoryFilterBar(
          selectedCategory: widget.selectedCategory,
          onSelectionChanged: widget.onSelectionChanged,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RepaintBoundary(
            child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              color: AppColors.primary,
              child: widget.messages.isEmpty && !widget.isLoading
                  ? ListView(
                      controller: widget.scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 100),
                        EmptyState(message: 'No updates yet'),
                      ],
                    )
                  : ListView.builder(
                      controller: widget.scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount:
                          widget.messages.length + (widget.isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == widget.messages.length) {
                          return _buildLoader();
                        }
                        final message = widget.messages[index];
                        return ChatBubble(
                          message: message,
                          onPin: widget.onPin,
                          onDelete: widget.onDelete,
                          onReport: widget.onReport,
                          onMute: widget.onMute,
                          onBan: widget.onBan,
                          onReact: widget.onReact,
                          isOrganizer: widget.isOrganizer,
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
                          linkPreviewData: widget.linkPreviews[message.message],
                          onLinkPreviewDataFetched:
                              widget.onLinkPreviewDataFetched,
                        );
                      },
                    ),
            ),
          ),
        ),
        MessageInput(
          onSendMessage: widget.onSendMessage,
          onActionTap: widget.onActionTap,
          mentionedMedia: widget.mentionedMedia,
          onCancelMention: widget.onCancelMention,
          onChanged: (text) {},
          members: widget.members,
        ),
      ],
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
