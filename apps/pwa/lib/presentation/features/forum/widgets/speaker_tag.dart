import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import '../services/forum_video_stream_service.dart';

class SpeakerTag extends StatelessWidget {
  final StreamParticipant activeParticipant;
  final double audioLevel;

  const SpeakerTag({
    super.key,
    required this.activeParticipant,
    required this.audioLevel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.accentColor.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            activeParticipant.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            color: activeParticipant.isMicMuted ? Colors.redAccent : context.accentColor,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            '${activeParticipant.name} (${activeParticipant.role})',
            style: AppTypography.interTight(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          if (!activeParticipant.isMicMuted)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(4, (index) {
                final multipliers = [0.65, 1.0, 0.8, 0.95];
                const baseHeight = 4.0;
                const maxHeight = 16.0;
                final activeHeight = baseHeight +
                    ((maxHeight - baseHeight) * audioLevel * multipliers[index])
                        .clamp(0.0, maxHeight - baseHeight);
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  width: 3,
                  height: activeHeight,
                  decoration: BoxDecoration(
                    color: audioLevel > 0.05 ? context.accentColor : Colors.white38,
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
