import 'dart:async';
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
    return ColoredBox(
      color: AppColors.primaryBackground,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: child,
      ),
    );
  }
}

/// Same crossfade as [SkeletonFade], but never mounts outgoing and incoming
/// children at once. AnimatedSwitcher's default layoutBuilder stacks both
/// during the transition — fine for plain widgets, but fatal when the
/// switched subtree contains a SliverOverlapInjector tied to a shared
/// NestedScrollView handle (two injectors racing to attach to one handle
/// throws). Use this instead of [SkeletonFade] wherever the switched child
/// lives inside a NestedScrollView-nested sliver tree.
class SkeletonFadeSingleMount extends StatelessWidget {
  final Widget child;

  const SkeletonFadeSingleMount({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.primaryBackground,
      child: AnimatedSwitcher(
        duration: SkeletonFade.duration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (currentChild, previousChildren) =>
            currentChild ?? const SizedBox.shrink(),
        child: child,
      ),
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

/// A small centered spinner that only appears if [delay] has elapsed while
/// still mounted — the common case (a fast fetch) shows nothing at all,
/// avoiding a flash of loading UI for a single frame; a genuinely slow
/// fetch still gets a "this is alive" signal instead of blank space that
/// could read as frozen. Replaces the old bubble-shaped skeleton for
/// message lists (Live Chat / Updates tabs) — deliberately not previewing
/// the list's shape anymore, just proving the app is working.
class DelayedLoadingSpinner extends StatefulWidget {
  final Duration delay;

  const DelayedLoadingSpinner({super.key, this.delay = const Duration(milliseconds: 300)});

  @override
  State<DelayedLoadingSpinner> createState() => _DelayedLoadingSpinnerState();
}

class _DelayedLoadingSpinnerState extends State<DelayedLoadingSpinner> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: context.accentColor),
        ),
      ),
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
