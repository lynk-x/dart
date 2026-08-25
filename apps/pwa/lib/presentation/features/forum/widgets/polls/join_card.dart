import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/forum_chat_cubit.dart';
import '../../cubit/forum_cubit.dart';
import 'poll_quiz_card_shell.dart';

enum JoinCardType { liveCall, liveStream, quiz }

enum JoinCardState { lobby, connecting, live, active, ended }

/// Polymorphic card component for inline chat announcements (Live Call, Live Stream, Quiz).
class JoinCard extends StatelessWidget {
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

  IconData get _icon {
    switch (type) {
      case JoinCardType.liveCall:
        return Icons.graphic_eq_rounded;
      case JoinCardType.liveStream:
        return Icons.videocam_rounded;
      case JoinCardType.quiz:
        return Icons.quiz_outlined;
    }
  }

  String get _headerLabel {
    switch (type) {
      case JoinCardType.liveCall:
        return 'Live Call';
      case JoinCardType.liveStream:
        return 'Live Stream';
      case JoinCardType.quiz:
        return 'Quiz';
    }
  }

  String get _buttonText {
    if (state == JoinCardState.ended) {
      switch (type) {
        case JoinCardType.liveCall:
          return 'Call Ended';
        case JoinCardType.liveStream:
          return 'Stream Ended';
        case JoinCardType.quiz:
          return 'Quiz Ended';
      }
    }

    if (state == JoinCardState.connecting) {
      return 'Connecting...';
    }

    if (state == JoinCardState.active) {
      switch (type) {
        case JoinCardType.liveCall:
          return 'On Call — Live';
        case JoinCardType.liveStream:
          return 'Watching — Live';
        case JoinCardType.quiz:
          return 'Rejoin — Live';
      }
    }

    switch (type) {
      case JoinCardType.liveCall:
        return 'Join Live Call';
      case JoinCardType.liveStream:
        return 'Watch Live Stream';
      case JoinCardType.quiz:
        return 'Join Quiz';
    }
  }

  void _broadcastJoinPresence(BuildContext context) {
    try {
      final chatCubit = context.read<ForumChatCubit>();
      final forumCubit = context.read<ForumCubit>();
      final userName = forumCubit.state.userName.isNotEmpty
          ? forumCubit.state.userName
          : 'A member';
      final isOrganizer = forumCubit.state.isOrganizer;
      final isPremium = forumCubit.state.isPremium;

      String joinMessage = '';
      if (type == JoinCardType.liveStream) {
        joinMessage = '👋 $userName joined the live stream';
      } else if (type == JoinCardType.liveCall) {
        joinMessage = '🎙️ $userName joined the live call';
      } else if (type == JoinCardType.quiz) {
        joinMessage = '🎯 $userName joined the quiz session';
      }

      if (joinMessage.isNotEmpty) {
        chatCubit.sendMessage(
          joinMessage,
          isOrganizer: isOrganizer,
          isPremium: isPremium,
        );
      }
    } catch (e) {
      debugPrint('[JoinCard] Error broadcasting join presence: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final onCardColor = PollQuizCardShell.onCardColor(isMe);
    final isLive = state == JoinCardState.live || state == JoinCardState.active;
    final isEnded = state == JoinCardState.ended;

    return PollQuizCardShell(
      isMe: isMe,
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
          if (title.isNotEmpty)
            Text(
              title,
              style: TextStyle(color: onCardColor, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(color: onCardColor.withValues(alpha: 0.7), fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isEnded || state == JoinCardState.connecting
                  ? null
                  : () {
                      _broadcastJoinPresence(context);
                      onAction?.call();
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
