import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

/// Typed value class representing a single entry in the live stage chat overlay.
/// Replaces the previous untyped `Map<String, dynamic>` pipeline for type safety
/// and zero-allocation reuse between builds.
class StageChatEntry {
  final String id;
  final String type; // 'chat' | 'announcement'
  final String sender;
  final String role;
  final String text;
  final DateTime createdAt;

  const StageChatEntry({
    required this.id,
    required this.type,
    required this.sender,
    required this.role,
    required this.text,
    required this.createdAt,
  });
}

/// Translucent live stream chat overlay displayed on the stage bottom-left.
class StageChatOverlay extends StatelessWidget {
  final List<StageChatEntry> combinedStream;

  const StageChatOverlay({
    super.key,
    required this.combinedStream,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 60,
      left: 16,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width * 0.7).clamp(200, 320),
          maxHeight: 160,
        ),
        child: ShaderMask(
          shaderCallback: (Rect bounds) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black, Colors.black],
              stops: [0.0, 0.2, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: CustomScrollView(
            reverse: true,
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entry = combinedStream[index];
                    final isAnnouncement = entry.type == 'announcement';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isAnnouncement
                              ? context.accentColor.withValues(alpha: 0.25)
                              : Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isAnnouncement
                                ? context.accentColor.withValues(alpha: 0.6)
                                : Colors.white12,
                            width: isAnnouncement ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isAnnouncement) ...[
                                  Icon(Icons.campaign_rounded, size: 12, color: context.accentColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    'ANNOUNCEMENT',
                                    style: AppTypography.interTight(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: context.accentColor,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Text(
                                  entry.sender,
                                  style: AppTypography.interTight(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (entry.role.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: isAnnouncement
                                          ? context.accentColor
                                          : Colors.white24,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      entry.role.toUpperCase(),
                                      style: AppTypography.inter(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: isAnnouncement ? Colors.black : Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              entry.text,
                              style: AppTypography.interTight(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: combinedStream.length,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
