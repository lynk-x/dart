import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

/// Shared card container for poll/quiz messages — same background color
/// rule, padding, and border radius as [PollCard]/`_QuizJoinCard`'s own
/// Container, factored out so the loading state renders inside an identical
/// shell rather than a bare centered spinner. The container itself (color,
/// size, position) never changes between loading and loaded — only the
/// content inside `child` does.
class PollQuizCardShell extends StatelessWidget {
  final bool isMe;
  final Widget child;

  const PollQuizCardShell({super.key, required this.isMe, required this.child});

  static Color cardColor(BuildContext context, bool isMe) =>
      isMe ? context.accentColor : AppColors.tertiary;

  static Color onCardColor(bool isMe) => isMe ? Colors.black : Colors.white;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor(context, isMe),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [child],
      ),
    );
  }
}

/// The type icon + "Poll"/"Quiz" label header row — identical in loading and
/// loaded states, so it's rendered once, immediately, from either state.
class PollQuizCardHeader extends StatelessWidget {
  final bool isQuiz;
  final bool isMe;
  final Widget? trailing;

  const PollQuizCardHeader({
    super.key,
    required this.isQuiz,
    required this.isMe,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final onCardColor = PollQuizCardShell.onCardColor(isMe);
    return Row(
      children: [
        Icon(
          isQuiz ? Icons.quiz_outlined : Icons.poll_outlined,
          color: onCardColor,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          isQuiz ? 'Quiz' : 'Poll',
          style: TextStyle(color: onCardColor, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// A placeholder bar standing in for not-yet-loaded text/buttons, sized to
/// match the real content's final layout so nothing resizes when it swaps
/// in. Tinted relative to the card background (not a fixed grey), since the
/// shell itself is already green (isMe) or dark grey (others).
class PollQuizSkeletonBar extends StatelessWidget {
  final bool isMe;
  final double height;
  final double? width;
  final EdgeInsetsGeometry margin;

  const PollQuizSkeletonBar({
    super.key,
    required this.isMe,
    required this.height,
    this.width,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: isMe ? Colors.black.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
