import 'package:flutter/material.dart';
import 'poll_quiz_card_shell.dart';

enum JoinCardType { liveCall, liveStream, quiz }

enum JoinCardState { lobby, connecting, live, active, ended }

class JoinCard extends StatefulWidget {
  final JoinCardType type;
  final JoinCardState state;
  final String title;
  final String? subtitle;
  final bool isMe;
  final VoidCallback? onAction;

  const JoinCard({
    super.key,
    required this.type,
    required this.state,
    required this.title,
    this.subtitle,
    this.isMe = false,
    this.onAction,
  });

  @override
  State<JoinCard> createState() => _JoinCardState();
}

class _JoinCardState extends State<JoinCard> {
  /// Guards against duplicate join announcements from rapid successive taps.
  bool _hasJoined = false;

  @override
  void didUpdateWidget(JoinCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear the guard if the session resets to lobby/connecting so the
    // user can broadcast a fresh join if they re-enter the session.
    if (widget.state != oldWidget.state &&
        (widget.state == JoinCardState.lobby ||
            widget.state == JoinCardState.connecting)) {
      _hasJoined = false;
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case JoinCardType.liveCall:
        return Icons.graphic_eq_rounded;
      case JoinCardType.liveStream:
        return Icons.videocam_rounded;
      case JoinCardType.quiz:
        return Icons.quiz_outlined;
    }
  }

  String get _headerLabel {
    switch (widget.type) {
      case JoinCardType.liveCall:
        return 'Audio Room';
      case JoinCardType.liveStream:
        return 'Video Broadcast';
      case JoinCardType.quiz:
        return 'Quiz';
    }
  }

  String get _buttonText {
    if (widget.state == JoinCardState.ended) {
      switch (widget.type) {
        case JoinCardType.liveCall:
          return 'Call Ended';
        case JoinCardType.liveStream:
          return 'Stream Ended';
        case JoinCardType.quiz:
          return 'Quiz Ended';
      }
    }

    if (widget.state == JoinCardState.connecting) {
      return 'Connecting...';
    }

    if (widget.state == JoinCardState.active) {
      switch (widget.type) {
        case JoinCardType.liveCall:
          return 'In Call';
        case JoinCardType.liveStream:
          return 'Watching';
        case JoinCardType.quiz:
          return 'In Quiz';
      }
    }

    switch (widget.type) {
      case JoinCardType.liveCall:
        return 'Join Call';
      case JoinCardType.liveStream:
        return 'Watch Stream';
      case JoinCardType.quiz:
        return 'Join Quiz';
    }
  }

  void _broadcastJoinPresence(BuildContext context) {
    if (_hasJoined) return;
    _hasJoined = true;
  }

  @override
  Widget build(BuildContext context) {
    final onCardColor = PollQuizCardShell.onCardColor(widget.isMe);
    final isLive = widget.state == JoinCardState.live || widget.state == JoinCardState.active;
    final isEnded = widget.state == JoinCardState.ended;

    return PollQuizCardShell(
      isMe: widget.isMe,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, color: onCardColor, size: 20),
              const SizedBox(width: 8),
              Text(
                _headerLabel,
                style: TextStyle(color: onCardColor, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (isLive)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'LIVE',
                      style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.title.isNotEmpty)
            Text(
              widget.title,
              style: TextStyle(color: onCardColor, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.subtitle!,
              style: TextStyle(color: onCardColor.withValues(alpha: 0.7), fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isEnded || widget.state == JoinCardState.connecting
                  ? null
                  : () {
                      _broadcastJoinPresence(context);
                      widget.onAction?.call();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                disabledBackgroundColor: onCardColor.withValues(alpha: 0.18),
                disabledForegroundColor: onCardColor.withValues(alpha: 0.4),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                _buttonText,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
