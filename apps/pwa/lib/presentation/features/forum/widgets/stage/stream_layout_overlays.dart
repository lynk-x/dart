import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/call_participant.dart';
import '../../services/stream_service.dart';
import 'soundwave_widget.dart';

/// Grid layout overlay rendering participant tiles.
class GridStageOverlay extends StatelessWidget {
  final ForumVideoStreamService videoService;

  /// This viewer's own audio level — drives only the self tile. Co-host tiles
  /// read their own level from videoService.participantAudioLevelNotifier.
  final ValueNotifier<double> audioLevelNotifier;
  final bool isCameraOn;
  final bool isMicMuted;
  final String viewType;
  final String? Function(String userId) participantSlotViewType;

  const GridStageOverlay({
    super.key,
    required this.videoService,
    required this.audioLevelNotifier,
    required this.isCameraOn,
    required this.isMicMuted,
    required this.participantSlotViewType,
    this.viewType = 'lynk-video-stage-view',
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: videoService.isLowBandwidthNotifier,
      builder: (context, isLowBandwidth, _) {
        // Previously sourced from activeParticipantsNotifier (forum
        // PRESENCE — anyone online), which meant this grid tiled up to 4
        // arbitrary online members, not actual participants, and the
        // isHostTile video-mount check only ever worked by accident for
        // whichever host happened to land in that list. participantsNotifier
        // (social.forum_call_participants) is the real registry of who is
        // actually publishing a track.
        return ValueListenableBuilder<Map<String, CallParticipant>>(
          valueListenable: videoService.participantsNotifier,
          builder: (context, callParticipants, _) {
            final selfId = Supabase.instance.client.auth.currentUser?.id;
            // This viewer's own tile reads the local mic/camera state; every
            // other tile reads that participant's own broadcast state, which
            // the registry entry carries. isHost here means "this viewer's
            // own tile" — the mapping below is the only place it's set.
            final participants = callParticipants.values
                .map((s) => StreamParticipant(
                      id: s.userId,
                      name: s.userName,
                      role: s.userId == selfId ? 'You' : 'Speaker',
                      isHost: s.userId == selfId,
                      isCameraOn:
                          s.userId == selfId ? isCameraOn : s.isCameraOn,
                      isMicMuted:
                          s.userId == selfId ? isMicMuted : s.isMicMuted,
                    ))
                .toList(growable: false);
            final count =
                participants.isEmpty ? 1 : participants.length.clamp(1, 4);
            final list = participants.isEmpty
                ? [
                    StreamParticipant(
                      id: 'host',
                      name: videoService.hostName.isNotEmpty
                          ? videoService.hostName
                          : 'Host',
                      role: 'Host',
                      isHost: true,
                      isCameraOn: isCameraOn,
                      isMicMuted: isMicMuted,
                    )
                  ]
                : participants;

            return Container(
              color: const Color(0xFF0F1115),
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
                  final double totalSpacingX =
                      (crossAxisCount - 1) * spacing + (padding * 2);
                  final double totalSpacingY =
                      (rowCount - 1) * spacing + (padding * 2);

                  final double tileWidth =
                      (availableWidth - totalSpacingX) / crossAxisCount;
                  final double tileHeight =
                      (availableHeight - totalSpacingY) / rowCount;
                  final double childAspectRatio =
                      (tileWidth > 0 && tileHeight > 0)
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
                        final p = list[index];
                        final isHostTile = p.isHost || index == 0;
                        // p already resolves to the right source (local for
                        // this viewer's own tile, the participant's broadcast
                        // state otherwise), so no per-tile override here —
                        // the old isHostTile ? local : p override made every
                        // index-0 tile show this viewer's own mic/camera.
                        final tileCamOn = p.isCameraOn;
                        final tileMicMuted = p.isMicMuted;
                        // Previously only the LOCAL viewer's own tile ever
                        // showed real video — every other tile fell back to
                        // the avatar placeholder unconditionally, since
                        // there was no per-speaker video element to mount.
                        // Now a co-host's slot (assigned by ForumVideoStage
                        // as their track is pulled) resolves to one of the
                        // fixed pre-registered slot view types.
                        final coHostSlotViewType =
                            isHostTile ? null : participantSlotViewType(p.id);
                        final hasRealVideo =
                            isHostTile || coHostSlotViewType != null;
                        // Own tile: the shared local level. Co-host tile:
                        // that participant's own analyser, so only the one
                        // actually speaking lights up.
                        final levelNotifier = p.isHost
                            ? audioLevelNotifier
                            : videoService.participantAudioLevelNotifier(p.id);

                        return ValueListenableBuilder<double>(
                          valueListenable: levelNotifier,
                          builder: (context, level, _) {
                            final isSpeakingNow = !tileMicMuted && level > 0.05;
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF161920),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSpeakingNow
                                        ? context.accentColor
                                        : Colors.white12,
                                    width: isSpeakingNow ? 2 : 1,
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    if (hasRealVideo &&
                                        tileCamOn &&
                                        kIsWeb &&
                                        !isLowBandwidth)
                                      Positioned.fill(
                                        child: HtmlElementView(
                                          viewType: isHostTile
                                              ? viewType
                                              : coHostSlotViewType!,
                                        ),
                                      ),
                                    if (!hasRealVideo ||
                                        !tileCamOn ||
                                        isLowBandwidth)
                                      Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircleAvatar(
                                              radius: 28,
                                              backgroundColor: isSpeakingNow
                                                  ? context.accentColor
                                                  : const Color(0xFF2A2E38),
                                              child: Text(
                                                p.name.isNotEmpty
                                                    ? p.name
                                                        .substring(0, 1)
                                                        .toUpperCase()
                                                    : '?',
                                                style: AppTypography.interTight(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white),
                                              ),
                                            ),
                                            if (isLowBandwidth) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                'Audio Only',
                                                style: AppTypography.interTight(
                                                    fontSize: 10,
                                                    color: Colors.amberAccent),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    Positioned(
                                      left: 10,
                                      bottom: 10,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.75),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (tileMicMuted) ...[
                                              const Icon(Icons.mic_off_rounded,
                                                  size: 12,
                                                  color: Colors.redAccent),
                                              const SizedBox(width: 4),
                                            ],
                                            Text(
                                              p.name,
                                              style: AppTypography.interTight(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 10,
                                      bottom: 10,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.75),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isSpeakingNow
                                                ? context.accentColor
                                                    .withValues(alpha: 0.5)
                                                : Colors.white12,
                                          ),
                                        ),
                                        child: SoundwaveWidget(
                                          isSpeaking: isSpeakingNow,
                                          audioLevelNotifier: levelNotifier,
                                          barColor: isSpeakingNow
                                              ? context.accentColor
                                              : Colors.white54,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            );
          },
        );
      },
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
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.indigoAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.present_to_all_rounded,
                      size: 42, color: Colors.indigoAccent),
                ),
                const SizedBox(height: 12),
                Text(
                  'Shared Presentation Stage',
                  style: AppTypography.interTight(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Screen share or slides deck actively broadcasting',
                  style: AppTypography.interTight(
                      fontSize: 12, color: Colors.white38),
                ),
              ],
            ),
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
                  hostName.isNotEmpty
                      ? hostName.substring(0, 1).toUpperCase()
                      : 'L',
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

/// Low-bandwidth fallback mode placeholder overlay.
class LowBandwidthFallbackOverlay extends StatelessWidget {
  final String hostName;

  const LowBandwidthFallbackOverlay({
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded,
                        size: 14, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      'Low-Bandwidth Mode • Audio Preserved',
                      style: AppTypography.interTight(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 36,
                backgroundColor: const Color(0xFF1E222B),
                child: Text(
                  hostName.isNotEmpty
                      ? hostName.substring(0, 1).toUpperCase()
                      : 'L',
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
                'Video feed paused to conserve network throughput',
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

/// Non-blocking badge for a LISTENER's own degraded connection — unlike
/// [LowBandwidthFallbackOverlay] (host-side, replaces the video entirely
/// because the HOST's own upload is bad for everyone), a listener is still
/// receiving something (Cloudflare's SFU may already be forwarding them a
/// lower simulcast layer); this just surfaces that their own experienced
/// quality is poor, since fetchListenerTelemetryStats has no verified way
/// to request a different layer from here.
class PoorConnectionBadge extends StatelessWidget {
  const PoorConnectionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
                Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
                size: 14,
                color: Colors.amber),
            const SizedBox(width: 4),
            Text(
              'Weak connection',
              style: AppTypography.interTight(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.amber,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
