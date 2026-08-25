import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import '../../services/stream_service.dart';
import 'animated_soundwave_widget.dart';

/// Grid layout overlay rendering participant tiles.
class GridStageOverlay extends StatelessWidget {
  final ForumVideoStreamService videoService;
  final double currentAudioLevel;

  const GridStageOverlay({
    super.key,
    required this.videoService,
    required this.currentAudioLevel,
  });

  @override
  Widget build(BuildContext context) {
    final participants = videoService.activeParticipantsNotifier.value;
    final count = participants.length.clamp(1, 4);

    return Container(
      color: const Color(0xFF0C0E12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final availableHeight = constraints.maxHeight;

          const double padding = 8.0;
          const double spacing = 8.0;

          int crossAxisCount = 2;
          if (count == 1) {
            crossAxisCount = 1;
          }

          final int rowCount = (count / crossAxisCount).ceil();
          final double totalSpacingX = (crossAxisCount - 1) * spacing + (padding * 2);
          final double totalSpacingY = (rowCount - 1) * spacing + (padding * 2);

          final double tileWidth = (availableWidth - totalSpacingX) / crossAxisCount;
          final double tileHeight = (availableHeight - totalSpacingY) / rowCount;
          final double childAspectRatio = (tileWidth > 0 && tileHeight > 0)
              ? tileWidth / tileHeight
              : 1.0;

          return Padding(
            padding: const EdgeInsets.all(padding),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: childAspectRatio,
              ),
              itemCount: count,
              itemBuilder: (context, index) {
                final p = participants[index];
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF161920),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: p.isSpeaking ? context.accentColor : Colors.white12,
                      width: p.isSpeaking ? 2 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: p.isSpeaking ? context.accentColor : const Color(0xFF2A2E38),
                          child: Text(
                            p.name.isNotEmpty ? p.name.substring(0, 1).toUpperCase() : '?',
                            style: AppTypography.interTight(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            p.name,
                            style: AppTypography.interTight(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: p.isSpeaking
                                  ? context.accentColor.withValues(alpha: 0.5)
                                  : Colors.white12,
                            ),
                          ),
                          child: AnimatedSoundwaveWidget(
                            isSpeaking: p.isSpeaking,
                            getAudioLevel: () => currentAudioLevel,
                            barColor: p.isSpeaking ? context.accentColor : Colors.white54,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Presentation / Deck mode overlay when broadcasting slides or screen share.
class PresentationStageOverlay extends StatelessWidget {
  const PresentationStageOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0C10),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF131722),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.indigoAccent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.present_to_all_rounded, size: 42, color: Colors.indigoAccent),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Shared Presentation Stage',
                      style: AppTypography.interTight(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Screen share or slides deck actively broadcasting',
                      style: AppTypography.interTight(fontSize: 12, color: Colors.white38),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Camera Off placeholder overlay displaying host avatar.
class CameraOffOverlay extends StatelessWidget {
  final String hostName;

  const CameraOffOverlay({
    super.key,
    required this.hostName,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: const Color(0xFF0F1115),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: const Color(0xFF1E222B),
                child: Text(
                  hostName.isNotEmpty ? hostName.substring(0, 1).toUpperCase() : 'L',
                  style: AppTypography.interTight(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                hostName,
                style: AppTypography.interTight(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Camera Off',
                style: AppTypography.interTight(
                  fontSize: 12,
                  color: Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
