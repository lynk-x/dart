import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';

class MessageInput extends StatefulWidget {
  final Function(String, ChatMessage?)? onSendMessage;
  final ChatMessage? replyTo;
  final ChatMessage? editingMessage;
  final ForumMedia? mentionedMedia;
  final VoidCallback? onCancelReply;
  final VoidCallback? onCancelMention;
  final VoidCallback? onCancelEdit;
  final VoidCallback? onActionTap;
  final VoidCallback? onCreatePollOrQuiz;
  final ValueChanged<String>? onChanged;
  final List<Map<String, dynamic>> members;
  final bool isReadOnly;
  final bool isMuted;
  final bool isOrganizer;

  const MessageInput({
    super.key,
    this.onSendMessage,
    this.replyTo,
    this.editingMessage,
    this.mentionedMedia,
    this.onCancelReply,
    this.onCancelMention,
    this.onCancelEdit,
    this.onActionTap,
    this.onCreatePollOrQuiz,
    this.onChanged,
    this.members = const [],
    this.isReadOnly = false,
    this.isMuted = false,
    this.isOrganizer = false,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _filteredMembers = [];
  bool _showMentions = false;


  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editingMessage != oldWidget.editingMessage && widget.editingMessage != null) {
      _controller.text = widget.editingMessage!.message;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    } else if (widget.editingMessage == null && oldWidget.editingMessage != null) {
      _controller.clear();
    }
  }

  void _handleSend() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onSendMessage?.call(_controller.text.trim(), widget.replyTo);
      _controller.clear();
      setState(() {
        _showMentions = false;
      });
    }
  }

  void _onChanged(String text) {
    widget.onChanged?.call(text);
    final atIndex = text.lastIndexOf('@');

    if (atIndex != -1 && atIndex >= text.length - 10) {
      final query = text.substring(atIndex + 1).toLowerCase();
      if (query.isNotEmpty && !RegExp(r'^[\w]+$').hasMatch(query)) {
        setState(() => _showMentions = false);
        return;
      }
      setState(() {
        _filteredMembers = widget.members.where((m) {
          final name = (m['user_name'] as String?)?.toLowerCase() ?? '';
          return name.contains(query);
        }).toList();
        _showMentions = _filteredMembers.isNotEmpty;
      });
    } else {
      setState(() {
        _showMentions = false;
      });
    }
  }

  void _selectMention(Map<String, dynamic> member) {
    final text = _controller.text;
    final atIndex = text.lastIndexOf('@');
    final handle = (member['user_name'] as String?) ?? (member['full_name'] as String?) ?? '';
    final newText = '${text.substring(0, atIndex)}@$handle ';
    _controller.text = newText;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: newText.length),
    );
    setState(() {
      _showMentions = false;
    });
  }

  String? _getDetectedCategory() {
    final trimmed = _controller.text.trimLeft();
    if (!trimmed.startsWith('#')) return null;

    final tagPart = trimmed.substring(1).trimLeft();
    for (final tag in ForumCategory.values) {
      final escapedTag = RegExp.escape(tag);
      final regExp = RegExp('^$escapedTag(?:\\s|[.,!?]|\$)', caseSensitive: false);
      if (regExp.hasMatch(tagPart)) {
        return tag;
      }
    }
    return null;
  }

  Widget _buildCategoryPreview(String category) {
    final color = ForumCategory.getColorForCategory(category, context.accentColor);
    final textColor = ThemeData.estimateBrightnessForColor(color) == Brightness.light
        ? Colors.black
        : Colors.white;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Container(
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
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This message will be categorized under #$category',
              style: AppTypography.inter(
                fontSize: 11,
                color: AppColors.primaryText.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detectedCategory = _getDetectedCategory();
    if (widget.isReadOnly && !widget.isOrganizer) {
      return Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.black26,
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline_rounded,
                color: Colors.white38, size: 16),
            const SizedBox(width: 8),
            Text(
              'This forum is in read-only mode',
              style: AppTypography.inter(fontSize: 13, color: Colors.white38),
            ),
          ],
        ),
      );
    }

    if (widget.isMuted) {
      return Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.black26,
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic_off_rounded, color: Colors.redAccent, size: 16),
            const SizedBox(width: 8),
            Text(
              'You have been muted in this forum',
              style: AppTypography.inter(fontSize: 13, color: Colors.redAccent),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.primaryBackground,
        border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showMentions) _buildMentionList(),
          if (widget.replyTo != null) _buildReplyPreview(),
          if (widget.editingMessage != null) _buildEditPreview(),
          if (widget.mentionedMedia != null) _buildMentionPreview(),
          if (detectedCategory != null) _buildCategoryPreview(detectedCategory),
          Row(
            children: [
              if (widget.isOrganizer && widget.onCreatePollOrQuiz != null)
                IconButton(
                  tooltip: 'Create poll or quiz',
                  icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 24),
                  onPressed: widget.onCreatePollOrQuiz,
                ),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _controller,
                    cursorColor: AppColors.secondaryText,
                    style: AppTypography.inter(color: AppColors.secondaryText),
                    decoration: InputDecoration(
                      hintText: widget.editingMessage != null ? 'Edit message...' : 'Type a message...',
                      hintStyle: AppTypography.inter(
                          color:
                              AppColors.secondaryText.withValues(alpha: 0.5)),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: _onChanged,
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: widget.editingMessage != null ? 'Save edit' : 'Send message',
                icon: Icon(
                    widget.editingMessage != null
                        ? Icons.check_rounded
                        : Icons.send_rounded,
                    color: Colors.white,
                    size: 26),
                onPressed: _handleSend,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        border:
            Border(left: BorderSide(color: context.accentColor, width: 3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_rounded, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Editing Message',
                  style: AppTypography.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: context.accentColor),
                ),
                Text(
                  widget.editingMessage!.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.inter(
                      fontSize: 11,
                      color: AppColors.primaryText.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.white54),
            onPressed: widget.onCancelEdit,
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        border:
            Border(left: BorderSide(color: context.accentColor, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.replyTo!.sender,
                  style: AppTypography.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: context.accentColor),
                ),
                Text(
                  _replyPreviewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.inter(
                      fontSize: 11,
                      color: AppColors.primaryText.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.white54),
            onPressed: widget.onCancelReply,
          ),
        ],
      ),
    );
  }

  /// Polls/quizzes carry no text on the message row itself — see the
  /// matching fallback in chat_bubble.dart's _ReplyPreview.
  String get _replyPreviewText {
    final replyTo = widget.replyTo!;
    if (replyTo.type.isPoll) return '📊 Poll';
    if (replyTo.type.isQuiz) return '🎯 Quiz';
    return replyTo.message;
  }

  Widget _buildMentionPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        border:
            Border(left: BorderSide(color: context.accentColor, width: 3)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: () {
              final url = widget.mentionedMedia!.thumbnailUrl?.isNotEmpty == true
                  ? widget.mentionedMedia!.thumbnailUrl!
                  : widget.mentionedMedia!.url.isNotEmpty
                      ? widget.mentionedMedia!.url
                      : null;
              if (url == null) {
                return Container(
                  width: 40,
                  height: 40,
                  color: Colors.grey[900],
                  child: const Icon(Icons.image, color: Colors.white24, size: 20),
                );
              }
              return CachedNetworkImage(
                imageUrl: url,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorWidget: (context, url, err) =>
                    const Icon(Icons.broken_image, color: Colors.white54),
              );
            }(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attached Media',
                  style: AppTypography.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: context.accentColor),
                ),
                Text(
                  widget.mentionedMedia!.mediaType.toUpperCase(),
                  style: AppTypography.inter(
                      fontSize: 11,
                      color: AppColors.primaryText.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.white54),
            onPressed: widget.onCancelMention,
          ),
        ],
      ),
    );
  }

  Widget _buildMentionList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _filteredMembers.length,
        itemBuilder: (context, index) {
          final member = _filteredMembers[index];
          return ListTile(
            leading: CircleAvatar(
              radius: 14,
              backgroundImage: member['avatar_url'] != null
                  ? CachedNetworkImageProvider(member['avatar_url'])
                  : null,
              child: member['avatar_url'] == null
                  ? const Icon(Icons.person, size: 16)
                  : null,
            ),
            title: Text(
              member['user_name'] as String? ?? 'Unknown',
              style: AppTypography.inter(fontSize: 13, color: Colors.white),
            ),
            onTap: () => _selectMention(member),
          );
        },
      ),
    );
  }
}
