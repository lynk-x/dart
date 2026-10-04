import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import '../services/stream_service.dart';

class SpeakerTag extends StatelessWidget {
  final StreamParticipant activeParticipant;
  final double audioLevel;

  const SpeakerTag({
    super.key,
    required this.activeParticipant,
    required this.audioLevel,
  });

  static const double _silenceFloor = 0.03;

  @override
  Widget build(BuildContext context) {
    final safeAudioLevel = (audioLevel.isNaN || audioLevel.isInfinite)
        ? 0.0
        : audioLevel.clamp(0.0, 1.0);

    final sensitiveAudioLevel = safeAudioLevel < _silenceFloor ? 0.0 : safeAudioLevel;

    final maxTagWidth = MediaQuery.of(context).size.width - 64;

    return Container(
      constraints: BoxConstraints(maxWidth: maxTagWidth > 120 ? maxTagWidth : 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '${activeParticipant.name} (${activeParticipant.role})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.interTight(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!activeParticipant.isMicMuted)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(4, (index) {
                final multipliers = [0.65, 1.0, 0.8, 0.95];
                const minHeight = 2.0; // true-silence floor — a hairline, not a resting bar
                const maxHeight = 16.0;
                final isSilent = sensitiveAudioLevel == 0.0;
                final activeHeight = isSilent
                    ? minHeight
                    : (minHeight + (maxHeight - minHeight) * sensitiveAudioLevel * multipliers[index])
                        .clamp(minHeight, maxHeight);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  width: 3,
                  height: activeHeight,
                  decoration: BoxDecoration(
                    color: isSilent ? Colors.white38 : context.accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'MUTED',
                style: AppTypography.interTight(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.redAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
