import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lynk_core/core.dart';
import 'package:intl/intl.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/core/network/lynk_cache_manager.dart';
import 'package:lynk_x/core/utils/image_optimizer.dart';
import 'action_bar.dart';
import 'polls/poll_body.dart';
import 'polls/quiz_card.dart';

/// A stylized chat bubble used for both Live Chat and Updates.
import 'link_preview.dart';
import 'parsed_message_text.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

/// A stylized chat bubble used for both Live Chat and Updates.
class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final Function(ChatMessage)? onReply;
  final Function(ChatMessage)? onPin;
  final Function(ChatMessage)? onReport;
  final Function(ChatMessage)? onMute;
  final Function(ChatMessage)? onBan;
  final Function(ChatMessage)? onDelete;
  final Function(ChatMessage)? onEdit;
  final VoidCallback? onTapBubble;
  final Function(String?)? onMediaTap;
  final Function(String)? onMentionTap;
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
    this.onDelete,
    this.onEdit,
    this.onTapBubble,
    this.onMediaTap,
    this.onMentionTap,
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
  @override
  Widget build(BuildContext context) {
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
              if (widget.message.isMe) ...[
                _buildStatusIndicator(),
                _buildReplyIcon(),
                _buildMoreIcon(),
              ],
              _buildBubble(),
              if (!widget.message.isMe) ...[
                _buildReplyIcon(),
                _buildMoreIcon(),
              ],
            ],
          ),
          if (widget.showActions) _buildActions(context),
        ],
      ),
    ),
    );
  }

  Widget _buildReplyIcon() {
    final isLargeScreen = MediaQuery.of(context).size.width > 600;
    if (!isLargeScreen || widget.onReply == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: IconButton(
        icon: const Icon(Icons.reply, size: 18, color: Colors.white24),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: () => widget.onReply?.call(widget.message),
        tooltip: 'Reply',
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
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
      child: ActionBar(
        mainAxisAlignment: widget.message.isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        items: [
          if (widget.onPin != null)
            ActionBarItem(
              label: widget.message.isPinned ? 'Unpin' : 'Pin',
              onTap: () async {
                final isPinned = widget.message.isPinned;
                final result = widget.onPin?.call(widget.message);
                // onPin may be a fire-and-forget void callback (older
                // wiring) or return Future<bool> (ForumCubit.pinMessage) —
                // only show success/failure feedback when it's the latter,
                // so a moderator actually finds out if the RPC's
                // can_manage_forum check rejected the pin.
                if (result is Future<bool>) {
                  final success = await result;
                  if (!context.mounted) return;
                  if (success) {
                    AppSnackBars.showInfo(context, isPinned ? 'Message unpinned' : 'Message pinned');
                  } else {
                    AppSnackBars.showError(context, 'Could not update pin.');
                  }
                } else {
                  AppSnackBars.showInfo(context, isPinned ? 'Message unpinned' : 'Message pinned');
                }
              },
              color: Colors.white70,
            ),

          if (widget.message.isMe && widget.onEdit != null)
            ActionBarItem(
              label: 'Edit',
              color: Colors.white70,
              onTap: () => widget.onEdit?.call(widget.message),
            ),

          if (widget.message.message.isNotEmpty)
            ActionBarItem(
              label: 'Copy',
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.message.message));
                AppSnackBars.showSuccess(context, 'Message copied to clipboard');
              },
              color: Colors.white70,
            ),

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
          if (!widget.message.isMe) ...[
            ActionBarItem(
              label: 'Report',
              color: Colors.red,
              onTap: () => widget.onReport?.call(widget.message),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSenderInfo() {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.message.isPremium) ...[
            const Icon(Icons.star_rounded, size: 12, color: AppColors.secondary),
            const SizedBox(width: 3),
          ],
          Text(
            '${widget.message.sender} • ${DateFormat('HH:mm').format(widget.message.createdAt)}',
            style: AppTypography.inter(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble() {
    if (widget.message.type.isPollOrQuiz) {
      return GestureDetector(
        onTap: widget.onTapBubble,
        onLongPress: widget.onLongPressBubble,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          child: _buildBody(Colors.white),
        ),
      );
    }

    final bgColor = widget.message.isMe
        ? context.accentColor
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
            if (widget.message.replyTo != null)
              _ReplyPreview(replyTo: widget.message.replyTo!),
            if (widget.message.imageUrl != null)
              _ImageContent(
                message: widget.message,
                onMediaTap: widget.onMediaTap,
              ),
            if (widget.message.category != null)
              _CategoryBadge(category: widget.message.category!),
            _buildBody(textColor),
          ],
        ),
      ),
    );
  }

  void _handleMentionTap(String username) {
    widget.onMentionTap?.call(username);
  }

  Widget _buildBody(Color textColor) {
    final pollsEnabled = context.read<FeatureFlagCubit>().isEnabled('enable_forum_polls');

    switch (widget.message.type) {
      case MessageType.chat:
      case MessageType.announcement:
        return _buildMessageContent(textColor);

      case MessageType.livechatPoll:
      case MessageType.updatePoll:
        return pollsEnabled
            ? PollBody(messageId: widget.message.id, isMe: widget.message.isMe)
            : const SizedBox.shrink();

      case MessageType.livechatQuiz:
      case MessageType.updateQuiz:
        return pollsEnabled
            ? QuizBody(messageId: widget.message.id, isMe: widget.message.isMe)
            : const SizedBox.shrink();
    }
  }

  Widget _buildMessageContent(Color textColor) {
    String displayMessage = widget.message.message;
    final category = widget.message.category;
    if (category != null) {
      final prefix = '#$category';
      final escapedPrefix = RegExp.escape(prefix);
      final regExp = RegExp('^$escapedPrefix(?:\\s+|\$)', caseSensitive: false);
      if (regExp.hasMatch(displayMessage)) {
        displayMessage = displayMessage.replaceFirst(regExp, '');
      }
    }

    if (displayMessage.isEmpty) {
      return const SizedBox.shrink();
    }

    final textStyle = AppTypography.inter(
        color: textColor, fontSize: 14, fontWeight: FontWeight.w500);
    final urlRegExp =
        RegExp(r'(?:(?:https?|ftp)://)?[\w/\-?=%.]+\.[\w/\-?=%.]+');
    final firstMatch = urlRegExp.firstMatch(displayMessage);

    if (firstMatch != null) {
      final urlContent =
          displayMessage.substring(firstMatch.start, firstMatch.end);
      final validUrl =
          urlContent.startsWith('http') ? urlContent : 'https://$urlContent';

      return ChatLinkPreview(
        url: validUrl,
        message: displayMessage,
        textStyle: textStyle,
        isMe: widget.message.isMe,
        data: widget.linkPreviewData,
        onFetched: (data) =>
            widget.onLinkPreviewDataFetched?.call(validUrl, data),
        onMentionTap: _handleMentionTap,
        isEdited: widget.message.isEdited,
      );
    }

    return ParsedMessageText(
      text: displayMessage,
      style: textStyle,
      accentColor: widget.message.isMe ? Colors.black : context.accentColor,
      onMentionTap: _handleMentionTap,
      onUrlTap: (url) => widget.onMediaTap?.call(url),
      isEdited: widget.message.isEdited,
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  final ChatMessage replyTo;

  const _ReplyPreview({required this.replyTo});
  String get _previewText {
    if (replyTo.type.isPoll) return '📊 Poll';
    if (replyTo.type.isQuiz) return '🎯 Quiz';
    return replyTo.message;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.reply, size: 12, color: Colors.white54),
          const SizedBox(width: 4),
          Text(
            _previewText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.inter(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ImageContent extends StatelessWidget {
  final ChatMessage message;
  final Function(String?)? onMediaTap;

  const _ImageContent({required this.message, this.onMediaTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl = ImageOptimizer.getOptimizedUrl(
      message.thumbnailUrl ?? message.imageUrl!,
      width: 500,
    );
    return GestureDetector(
      onTap: () => onMediaTap?.call(message.imageUrl),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          cacheManager: LynkCacheManager.instance,
          fit: BoxFit.cover,
          memCacheWidth: 400,
          placeholder: (context, url) => Container(
            height: 120,
            color: Colors.grey[900],
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 1.5, color: context.accentColor),
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
}

class _CategoryBadge extends StatelessWidget {
  final String category;

  const _CategoryBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    final color = ForumCategory.getColorForCategory(category, context.accentColor);
    final textColor = ThemeData.estimateBrightnessForColor(color) == Brightness.light
        ? Colors.black
        : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '#$category',
          style: AppTypography.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }
}



