import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';

class MessageInput extends StatefulWidget {
  final Function(String, ChatMessage?)? onSendMessage;
  final ChatMessage? replyTo;
  final ForumMedia? mentionedMedia;
  final VoidCallback? onCancelReply;
  final VoidCallback? onCancelMention;
  final VoidCallback? onActionTap;
  final ValueChanged<String>? onChanged;
  final List<Map<String, dynamic>> members;

  const MessageInput({
    super.key,
    this.onSendMessage,
    this.replyTo,
    this.mentionedMedia,
    this.onCancelReply,
    this.onCancelMention,
    this.onActionTap,
    this.onChanged,
    this.members = const [],
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _filteredMembers = [];
  bool _showMentions = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      setState(() {
        _filteredMembers = widget.members.where((m) {
          final name = (m['full_name'] as String?)?.toLowerCase() ?? '';
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
    final newText = '${text.substring(0, atIndex)}@${member['full_name']} ';
    _controller.text = newText;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: newText.length),
    );
    setState(() {
      _showMentions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.primaryBackground,
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showMentions) _buildMentionList(),
          if (widget.replyTo != null) _buildReplyPreview(),
          if (widget.mentionedMedia != null) _buildMentionPreview(),
          Row(
            children: [
              // Action button hidden for MVP
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
                      hintText: 'Type a message...',
                      hintStyle: AppTypography.inter(
                          color:
                              AppColors.secondaryText.withOpacity(0.5)),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: _onChanged,
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _handleSend,
                child: const Icon(Icons.send, color: Colors.white, size: 30),
              ),
            ],
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
        color: Colors.white.withOpacity(0.1),
        border:
            const Border(left: BorderSide(color: AppColors.primary, width: 3)),
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
                      color: AppColors.primary),
                ),
                Text(
                  widget.replyTo!.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.inter(
                      fontSize: 11,
                      color: AppColors.primaryText.withOpacity(0.7)),
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

  Widget _buildMentionPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        border:
            const Border(left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CachedNetworkImage(
              imageUrl: widget.mentionedMedia!.thumbnailUrl ??
                  widget.mentionedMedia!.url,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorWidget: (context, url, err) =>
                  const Icon(Icons.broken_image, color: Colors.white54),
            ),
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
                      color: AppColors.primary),
                ),
                Text(
                  widget.mentionedMedia!.mediaType.toUpperCase(),
                  style: AppTypography.inter(
                      fontSize: 11,
                      color: AppColors.primaryText.withOpacity(0.7)),
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
              member['full_name'] ?? 'Unknown',
              style: AppTypography.inter(fontSize: 13, color: Colors.white),
            ),
            onTap: () => _selectMention(member),
          );
        },
      ),
    );
  }
}
