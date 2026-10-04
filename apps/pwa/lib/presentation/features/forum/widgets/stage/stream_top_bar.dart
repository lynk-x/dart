import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import '../../services/stream_service.dart';

/// Top bar overlay on the video stage displaying session duration, spectator badge, telemetry toggle, screen share, camera flip, and exit/minimize buttons.
/// Uses a [ValueNotifier<int>] for session duration so only the duration text
/// rebuilds on each timer tick — not the entire parent stage widget.
class StageTopBar extends StatelessWidget {
  final ForumVideoStreamService videoService;
  /// Notifier updated every second by the parent's duration timer.
  final ValueNotifier<int> sessionDurationNotifier;
  final bool showTelemetryOverlay;
  final bool isHost;
  /// Whether this viewer currently publishes a track — host OR co-host.
  /// Camera flip is about THIS user's own device camera, so it's gated on
  /// this rather than [isHost] (screen share stays host-only — see its
  /// own IconButton below — camera flip does not).
  final bool isPublishingRole;
  final bool isScreenSharing;
  final bool isFrontCamera;
  final bool isMicMuted;
  final bool isCameraOn;
  final VoidCallback onToggleTelemetry;
  final VoidCallback onShowTelemetryModal;
  final VoidCallback onMinimize;
  final VoidCallback? onToggleScreenShare;
  final VoidCallback? onFlipCamera;
  final VoidCallback? onToggleMic;
  final VoidCallback? onToggleCamera;

  const StageTopBar({
    super.key,
    required this.videoService,
    required this.sessionDurationNotifier,
    required this.showTelemetryOverlay,
    this.isHost = false,
    this.isPublishingRole = false,
    this.isScreenSharing = false,
    this.isFrontCamera = true,
    this.isMicMuted = false,
    this.isCameraOn = true,
    required this.onToggleTelemetry,
    required this.onShowTelemetryModal,
    required this.onMinimize,
    this.onToggleScreenShare,
    this.onFlipCamera,
    this.onToggleMic,
    this.onToggleCamera,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // TOP LEFT: MINIMIZE / BROWSER PIP TRIGGER
          InkWell(
            onTap: onMinimize,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12),
              ),
              child: const Icon(
                Icons.picture_in_picture_alt_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),

          // TOP RIGHT: CONTROLS & COMBINED LIVE / SPECTATOR BADGE
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // SCREEN SHARE BUTTON
              IconButton(
                icon: Icon(
                  isScreenSharing
                      ? Icons.stop_screen_share_rounded
                      : Icons.screen_share_rounded,
                  color: !isHost
                      ? Colors.white24
                      : (isScreenSharing ? context.accentColor : Colors.white70),
                  size: 20,
                ),
                onPressed: !isHost ? null : onToggleScreenShare,
                tooltip: isScreenSharing ? 'Stop Screen Share' : 'Share Screen',
              ),

              // FLIP CAMERA BUTTON
              IconButton(
                icon: Icon(
                  Icons.flip_camera_ios_rounded,
                  color: !isPublishingRole
                      ? Colors.white24
                      : (isFrontCamera ? Colors.white70 : context.accentColor),
                  size: 20,
                ),
                onPressed: !isPublishingRole ? null : onFlipCamera,
                tooltip: 'Flip Camera',
              ),

              // TELEMETRY TOGGLE BUTTON (Without background container)
              GestureDetector(
                onLongPress: onShowTelemetryModal,
                child: IconButton(
                  icon: Icon(
                    Icons.analytics_rounded,
                    size: 20,
                    color: showTelemetryOverlay ? context.accentColor : Colors.white70,
                  ),
                  onPressed: onToggleTelemetry,
                  tooltip: 'Telemetry Stats',
                ),
              ),
              const SizedBox(width: 4),

              // COMBINED LIVE/RECONNECTING & SPECTATOR COUNT BADGE
              ValueListenableBuilder<bool>(
                valueListenable: videoService.isReconnectingNotifier,
                builder: (context, isReconnecting, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isReconnecting) ...[
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.amber),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'RECONNECTING',
                            style: AppTypography.interTight(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ] else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'LIVE',
                              style: AppTypography.interTight(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        const Icon(Icons.remove_red_eye_rounded, size: 13, color: Colors.white70),
                        const SizedBox(width: 5),
                        Text(
                          '${videoService.spectatorCount}',
                          style: AppTypography.interTight(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
