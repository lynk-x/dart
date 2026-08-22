import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import '../services/forum_video_stream_service.dart';

class GuestThumbnailStrip extends StatelessWidget {
  final List<StreamParticipant> participants;
  final String pinnedId;
  final bool isHost;
  final ValueChanged<String> onPinSpeaker;
  final VoidCallback? onAddStageSpeaker;

  const GuestThumbnailStrip({
    super.key,
    required this.participants,
    required this.pinnedId,
    required this.isHost,
    required this.onPinSpeaker,
    this.onAddStageSpeaker,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: participants.length + (isHost ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == participants.length && isHost) {
            return InkWell(
              onTap: onAddStageSpeaker,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 76,
                height: 98,
                decoration: BoxDecoration(
                  color: const Color(0xFF161920).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24, width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: context.accentColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person_add_alt_1_rounded,
                        color: context.accentColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Add Stage',
                      style: AppTypography.interTight(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final p = participants[index];
          final isPinned = p.id == pinnedId;

          return InkWell(
            onTap: () => onPinSpeaker(p.id),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 76,
              height: 98,
              decoration: BoxDecoration(
                color: const Color(0xFF121418),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isPinned ? context.accentColor : Colors.white12,
                  width: isPinned ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: const Color(0xFF1A1D24),
                        child: Center(
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: isPinned
                                ? context.accentColor
                                : const Color(0xFF2C313C),
                            child: Text(
                              p.name.substring(0, 1).toUpperCase(),
                              style: AppTypography.interTight(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          p.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          color: p.isMicMuted ? Colors.redAccent : context.accentColor,
                          size: 10,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                        color: Colors.black.withValues(alpha: 0.75),
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppTypography.interTight(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
