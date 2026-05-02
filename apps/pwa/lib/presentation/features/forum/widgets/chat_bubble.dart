import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lynk_core/core.dart';
import 'package:intl/intl.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/core/network/lynk_cache_manager.dart';
import 'action_bar.dart';
import 'polls/poll_attachment.dart';

/// A stylized chat bubble used for both Live Chat and Updates.
import 'link_preview.dart';

/// A stylized chat bubble used for both Live Chat and Updates.
class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final Function(ChatMessage)? onReply;
  final Function(ChatMessage)? onPin;
  final Function(ChatMessage)? onReport;
  final Function(ChatMessage)? onMute;
  final Function(ChatMessage)? onBan;
  final Function(ChatMessage, String)? onReact;
  final Function(ChatMessage)? onDelete;
  final VoidCallback? onTapBubble;
  final Function(String?)? onMediaTap;
  final Function(ChatMessage)? onReactionTap;
  final VoidCallback? onLongPressBubble;
  final bool isOrganizer;
  final LinkPreviewData? linkPreviewData;
  final Function(String, LinkPreviewData)? onLinkPreviewDataFetched;
  final bool showActions;
  final bool showSenderInfo;
  final bool isGrouped;

  const ChatBubble({
    super.key,
    required this.message,
    this.onReply,
    this.onPin,
    this.onReport,
    this.onMute,
    this.onBan,
    this.onReact,
    this.onDelete,
    this.onTapBubble,
    this.onMediaTap,
    this.onReactionTap,
    this.onLongPressBubble,
    this.isOrganizer = false,
    this.linkPreviewData,
    this.onLinkPreviewDataFetched,
    this.showActions = false,
    this.showSenderInfo = true,
    this.isGrouped = false,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final blockCubit = BlocProvider.of<BlockCubit>(context, listen: true);
    final isBlocked = blockCubit.isBlocked(widget.message.userId);
    final shouldBlur = isBlocked && !_revealed;

    return Align(
      alignment:
          widget.message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: widget.isGrouped ? 2 : 8,
          bottom: widget.showSenderInfo ? 8 : 2,
        ),
        child: Column(
        crossAxisAlignment: widget.message.isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!widget.message.isMe && widget.showSenderInfo) _buildSenderInfo(),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: widget.message.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.message.isMe) _buildStatusIndicator(),
              if (shouldBlur) _buildBlurredBubble() else _buildBubble(),
              if (widget.message.isMe) _buildMoreIcon(),
              if (!widget.message.isMe) _buildMoreIcon(),
            ],
          ),
          if (widget.showActions) _buildActions(context),
        ],
      ),
    ),
    );
  }

  Widget _buildMoreIcon() {
    final isLargeScreen = MediaQuery.of(context).size.width > 600;
    if (!isLargeScreen) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: IconButton(
        icon: const Icon(Icons.more_vert, size: 18, color: Colors.white24),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: widget.onLongPressBubble,
        tooltip: 'Actions',
      ),
    );
  }

  Widget _buildStatusIndicator() {
    if (widget.message.isSending) {
      return const Padding(
        padding: EdgeInsets.only(right: 6, bottom: 4),
        child: SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white38),
        ),
      );
    }
    if (widget.message.hasError) {
      return const Padding(
        padding: EdgeInsets.only(right: 6, bottom: 4),
        child: Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildActions(BuildContext context) {
    final blockCubit = context.read<BlockCubit>();
    final isBlocked = blockCubit.isBlocked(widget.message.userId);

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
      child: ActionBar(
        mainAxisAlignment: widget.message.isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        items: [
          if (widget.onPin != null)
            ActionBarItem(
              label: 'Pin',
              onTap: () => widget.onPin?.call(widget.message),
              color: AppColors.primary,
            ),
          if (widget.isOrganizer && !widget.message.isMe) ...[
            if (widget.onMute != null)
              ActionBarItem(
                label: 'Mute',
                onTap: () => widget.onMute?.call(widget.message),
                color: Colors.orangeAccent,
              ),
            if (widget.onBan != null)
              ActionBarItem(
                label: 'Ban',
                onTap: () => widget.onBan?.call(widget.message),
                color: Colors.red,
              ),
          ],
          if (!widget.message.isMe) ...[
            ActionBarItem(
              label: isBlocked ? 'Unblock' : 'Block',
              onTap: () {
                if (isBlocked) {
                  blockCubit.unblockUser(widget.message.userId);
                } else {
                  blockCubit.blockUser(widget.message.userId);
                }
              },
              color: Colors.redAccent,
            ),
            ActionBarItem(
              label: 'Report',
              onTap: () => widget.onReport?.call(widget.message),
            ),
          ],
          if (widget.message.isMe && widget.onDelete != null)
            ActionBarItem(
              label: 'Delete',
              color: Colors.redAccent,
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text('Delete message?', style: TextStyle(color: Colors.white)),
                    content: const Text(
                      'This message will be removed for everyone.',
                      style: TextStyle(color: Colors.white54),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) widget.onDelete?.call(widget.message);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBlurredBubble() {
    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.tertiary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Opacity(
                opacity: 0.5,
                child: _buildBubble(),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, color: Colors.white60, size: 20),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => setState(() => _revealed = true),
                  child: const Text('Reveal',
                      style: TextStyle(color: AppColors.primary, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSenderInfo() {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        '${widget.message.sender} • ${DateFormat('HH:mm').format(widget.message.createdAt)}',
        style: AppTypography.inter(color: Colors.white38, fontSize: 10),
      ),
    );
  }

  Widget _buildBubble() {
    final bgColor = widget.message.isMe
        ? AppColors.primary
        : AppColors.tertiary;
    final textColor = widget.message.isMe ? Colors.black : Colors.white;

    return GestureDetector(
      onTap: widget.onTapBubble,
      onLongPress: widget.onLongPressBubble,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(widget.message.isMe ? 16 : (widget.isGrouped ? 12 : 0)),
            bottomRight: Radius.circular(widget.message.isMe ? (widget.isGrouped ? 12 : 0) : 12),
          ),
          border: Border.all(color: Colors.transparent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message.replyTo != null) _buildReplyPreview(),
            if (widget.message.imageUrl != null) _buildImageContent(),
            if (widget.message.category != null) _buildCategoryBadge(),
            _buildMessageContent(textColor),
            if (widget.message.questionnaireId != null &&
                context.read<FeatureFlagCubit>().isEnabled('enable_forum_polls'))
              PollAttachment(questionnaireId: widget.message.questionnaireId!),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.reply, size: 12, color: Colors.white54),
          const SizedBox(width: 4),
          Text(
            widget.message.replyTo!.message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.inter(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildImageContent() {
    final imageUrl = widget.message.thumbnailUrl ?? widget.message.imageUrl!;
    return GestureDetector(
      onTap: () => widget.onMediaTap?.call(widget.message.imageUrl),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          cacheManager: LynkCacheManager.instance,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            height: 120,
            color: Colors.grey[900],
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary),
            ),
          ),
          errorWidget: (context, url, err) => Container(
            height: 120,
            color: Colors.grey[900],
            child: const Center(
              child: Icon(Icons.broken_image, color: Colors.white24),
            ),
          ),
        ),
      ),
    );
  }

  static const _categoryColors = {
    'urgent': Color(0xFFFF4444),
    'activity': Color(0xFF00AAFF),
    'Q&A': Color(0xFFFFAA00),
    'Resources': Color(0xFF44DD88),
    'Rules': Color(0xFFAA88FF),
  };

  Widget _buildCategoryBadge() {
    final category = widget.message.category!;
    final color = _categoryColors[category] ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
        ),
        child: Text(
          '#$category',
          style: AppTypography.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageContent(Color textColor) {
    final textStyle = AppTypography.inter(
        color: textColor, fontSize: 14, fontWeight: FontWeight.w500);
    final urlRegExp =
        RegExp(r'(?:(?:https?|ftp)://)?[\w/\-?=%.]+\.[\w/\-?=%.]+');
    final firstMatch = urlRegExp.firstMatch(widget.message.message);

    if (firstMatch != null) {
      final urlContent =
          widget.message.message.substring(firstMatch.start, firstMatch.end);
      final validUrl =
          urlContent.startsWith('http') ? urlContent : 'https://$urlContent';

      return ChatLinkPreview(
        url: validUrl,
        message: widget.message.message,
        textStyle: textStyle,
        data: widget.linkPreviewData,
        onFetched: (data) =>
            widget.onLinkPreviewDataFetched?.call(validUrl, data),
      );
    }

    return Text(widget.message.message, style: textStyle);
  }
}
