import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:intl/intl.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'action_bar.dart';
import 'polls/poll_attachment.dart';

/// A stylized chat bubble used for both Live Chat and Updates.
class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final Function(ChatMessage)? onReply;
  final Function(ChatMessage)? onPin;
  final Function(ChatMessage)? onReport;
  final Function(ChatMessage)? onMute;
  final Function(ChatMessage)? onBan;
  final Function(ChatMessage, String)? onReact;
  final VoidCallback? onMediaTap;
  final VoidCallback? onLongPressBubble;
  final bool isOrganizer;
  final LinkPreviewData? linkPreviewData;
  final Function(String, LinkPreviewData)? onLinkPreviewDataFetched;
  final bool showActions;

  const ChatBubble({
    super.key,
    required this.message,
    this.onReply,
    this.onPin,
    this.onReport,
    this.onMute,
    this.onBan,
    this.onReact,
    this.onMediaTap,
    this.onLongPressBubble,
    this.isOrganizer = false,
    this.linkPreviewData,
    this.onLinkPreviewDataFetched,
    this.showActions = false,
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

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      alignment:
          widget.message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: widget.message.isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!widget.message.isMe) _buildSenderInfo(),
          if (shouldBlur) _buildBlurredBubble() else _buildBubble(),
          if (widget.showActions) _buildActions(context),
        ],
      ),
    );
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
          if (!widget.message.isMe) ...[
            ActionBarItem(
              label: 'Report',
              onTap: () => widget.onReport?.call(widget.message),
            ),
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
          ],
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
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
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
        ? AppColors.primary.withValues(alpha: 0.15)
        : Colors.white.withValues(alpha: 0.05);
    final textColor = widget.message.isMe ? AppColors.primary : Colors.white;

    return GestureDetector(
      onLongPress: widget.onLongPressBubble,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(widget.message.isMe ? 16 : 0),
            bottomRight: Radius.circular(widget.message.isMe ? 0 : 16),
          ),
          border: Border.all(
              color: widget.message.isMe
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message.replyTo != null) _buildReplyPreview(),
            if (widget.message.imageUrl != null) _buildImageContent(),
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: Colors.black26, borderRadius: BorderRadius.circular(8)),
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
    return GestureDetector(
      onTap: widget.onMediaTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
        child: Image.network(
            widget.message.thumbnailUrl ?? widget.message.imageUrl!,
            fit: BoxFit.cover),
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

      return _CustomLinkPreview(
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

class _CustomLinkPreview extends StatefulWidget {
  final String url;
  final String message;
  final TextStyle textStyle;
  final LinkPreviewData? data;
  final Function(LinkPreviewData)? onFetched;

  const _CustomLinkPreview({
    required this.url,
    required this.message,
    required this.textStyle,
    this.data,
    this.onFetched,
  });

  @override
  State<_CustomLinkPreview> createState() => _CustomLinkPreviewState();
}

class _CustomLinkPreviewState extends State<_CustomLinkPreview> {
  @override
  void initState() {
    super.initState();
    if (widget.data == null) {
      _fetchMetadata();
    }
  }

  Future<void> _fetchMetadata() async {
    // Actually fetching metadata here would require http/html packages.
    // For now, satisfy the UI with a placeholder or simple fetcher if available.
    // I'll define a basic metadata fetcher.
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data == null) return Text(widget.message, style: widget.textStyle);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.message, style: widget.textStyle),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.data!.image != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      widget.data!.image!,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              if (widget.data!.title != null)
                Text(
                  widget.data!.title!,
                  style: widget.textStyle.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              if (widget.data!.description != null)
                Text(
                  widget.data!.description!,
                  style: widget.textStyle.copyWith(fontSize: 12, color: Colors.white70),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
