import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

/// Warns members before an `open` forum locks to read-only, converting what
/// was previously a silent cliff (input just disappears one day) into an
/// expected event. The lock itself is still driven entirely server-side
/// (weekly cron, `infra.system_config['community']['forum_auto_read_only_days']`
/// days after the event ends) — this widget only computes when to *show* the
/// warning from the same inputs, it doesn't control the lock.
class InputAccessoryBar extends StatelessWidget {
  final DateTime? eventEndsAt;
  final String forumStatus;
  final int autoReadOnlyDays;

  const InputAccessoryBar({
    super.key,
    required this.eventEndsAt,
    required this.forumStatus,
    required this.autoReadOnlyDays,
  });

  @override
  Widget build(BuildContext context) {
    final text = _warningText();
    if (text == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule_rounded, color: Colors.white54, size: 15),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.inter(fontSize: 12, color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Null when there's nothing to warn about: forum's already locked, or the
  /// event hasn't ended yet (the grace window hasn't started). Shown for the
  /// entire grace window once it starts, not just the final day — the
  /// countdown granularity coarsens as it gets further out (days, then
  /// hours) so it reads as informative rather than alarming this early.
  String? _warningText() {
    if (forumStatus != 'open') return null;
    final endsAt = eventEndsAt;
    if (endsAt == null) return null;
    if (DateTime.now().isBefore(endsAt)) return null;

    final lockAt = endsAt.add(Duration(days: autoReadOnlyDays));
    final remaining = lockAt.difference(DateTime.now());

    if (remaining.isNegative) return null; // Lock is due any moment — cron hasn't run yet, not worth a stale countdown.

    if (remaining.inDays >= 1) {
      final days = remaining.inDays;
      return 'This forum becomes read-only in $days ${days == 1 ? 'day' : 'days'}';
    }
    if (remaining.inHours >= 1) {
      final hours = remaining.inHours;
      return 'This forum becomes read-only in $hours ${hours == 1 ? 'hour' : 'hours'}';
    }
    return 'This forum becomes read-only soon';
  }
}
