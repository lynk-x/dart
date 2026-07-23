import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

/// Shared loading-skeleton pieces for the forum feature's list-shaped
/// content (chat/updates message lists, media grid, presence roster,
/// session schedule). Each mirrors the size/shape/color of the real content
/// it stands in for, so nothing resizes or recolors abruptly once data
/// arrives — same principle as [PollQuizCardShell]'s progressive reveal,
/// applied to repeating-item lists instead of a single card.

/// Crossfades between a loading skeleton and its resolved content so the
/// swap doesn't read as a hard layout jump. Wrap the skeleton-or-content
/// conditional in this instead of returning either widget directly; give
/// each branch a distinct [Key] (e.g. `ValueKey('skeleton')` /
/// `ValueKey('content')`) so [AnimatedSwitcher] treats them as separate
/// subtrees to fade between rather than diffing one into the other.
class SkeletonFade extends StatelessWidget {
  final Widget child;

  const SkeletonFade({super.key, required this.child});

  static const duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}

/// A single placeholder rectangle. Tint defaults to a neutral dark-surface
/// tone; pass [onGreen] when the placeholder sits on the accent-green "my
/// message" bubble background instead, so it stays visible there too.
class SkeletonBlock extends StatelessWidget {
  final double height;
  final double? width;
  final BorderRadius borderRadius;
  final bool onGreen;

  const SkeletonBlock({
    super.key,
    required this.height,
    this.width,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.onGreen = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: onGreen ? Colors.black.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.06),
        borderRadius: borderRadius,
      ),
    );
  }
}

/// Stands in for a single [ChatBubble] while the message list's first page
/// is loading — same bubble-tail radius rule (`ChatBubble._buildBubble`),
/// same isMe-based color (accent green vs `AppColors.tertiary`), same
/// left/right alignment. Width varies per instance so a row of these
/// doesn't look mechanically uniform.
class SkeletonChatBubble extends StatelessWidget {
  final bool isMe;
  final double widthFactor;

  const SkeletonChatBubble({super.key, required this.isMe, this.widthFactor = 0.55});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: FractionallySizedBox(
          widthFactor: widthFactor,
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: isMe ? context.accentColor.withValues(alpha: 0.35) : AppColors.tertiary,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isMe ? 16 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A short run of alternating skeleton bubbles, used wherever a message
/// list (Live Chat or Updates tab) is loading its first page. Shared
/// between both tabs so their loading treatment can't drift independently.
class SkeletonChatBubbleList extends StatelessWidget {
  const SkeletonChatBubbleList({super.key});

  static const _pattern = [
    (isMe: false, width: 0.62),
    (isMe: true, width: 0.48),
    (isMe: false, width: 0.7),
    (isMe: false, width: 0.4),
    (isMe: true, width: 0.58),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final row in _pattern)
          SkeletonChatBubble(isMe: row.isMe, widthFactor: row.width),
      ],
    );
  }
}

/// Stands in for a [UserPresenceCard] row in the presence drawer — same
/// `AppColors.surface` card background, radius 8, `Colors.white12` border as
/// the real card's non-primary state.
class SkeletonPresenceRow extends StatelessWidget {
  const SkeletonPresenceRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SkeletonBlock(height: 14, width: 120),
          SizedBox(height: 6),
          SkeletonBlock(height: 11, width: 70),
        ],
      ),
    );
  }
}

/// A short list of [SkeletonPresenceRow]s for the presence drawer's
/// first-load state.
class SkeletonPresenceList extends StatelessWidget {
  const SkeletonPresenceList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        SkeletonPresenceRow(),
        SkeletonPresenceRow(),
        SkeletonPresenceRow(),
        SkeletonPresenceRow(),
      ],
    );
  }
}

/// Stands in for a `_SessionCard` in the schedule screen — same
/// `AppColors.surface` background, radius 16, `AppColors.tertiary` inactive
/// border.
class SkeletonSessionCard extends StatelessWidget {
  const SkeletonSessionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.tertiary),
      ),
      padding: const EdgeInsets.all(14),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBlock(height: 15, width: 160),
          SizedBox(height: 8),
          SkeletonBlock(height: 11, width: 90),
        ],
      ),
    );
  }
}

/// A short schedule-shaped list for the sessions screen's first-load state
/// — a date-label bar followed by a couple of session cards, repeated once,
/// echoing the real screen's day-grouped layout without claiming specific
/// dates/times it doesn't have yet.
class SkeletonSessionsList extends StatelessWidget {
  const SkeletonSessionsList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 12, left: 4),
          child: SkeletonBlock(height: 12, width: 130, borderRadius: BorderRadius.circular(4)),
        ),
        const SkeletonSessionCard(),
        const SizedBox(height: 8),
        const SkeletonSessionCard(),
      ],
    );
  }
}

/// Stands in for a media grid tile — same `Colors.grey[900]` fill and
/// radius-8 clipping as the real thumbnail/placeholder.
class SkeletonMediaTile extends StatelessWidget {
  const SkeletonMediaTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(color: Colors.grey[900]),
    );
  }
}

/// A grid of [SkeletonMediaTile]s matching the real media grid's column
/// count and spacing, for the media tab's first-load state.
class SkeletonMediaGrid extends StatelessWidget {
  const SkeletonMediaGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = MediaQuery.of(context).size.width < 600 ? 3 : 4;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.3,
      ),
      itemCount: crossAxisCount * 3,
      itemBuilder: (context, index) => const SkeletonMediaTile(),
    );
  }
}
