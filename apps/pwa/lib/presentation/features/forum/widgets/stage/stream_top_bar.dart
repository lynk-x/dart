import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import '../../services/stream_service.dart';

/// Top bar overlay on the video stage displaying session duration, spectator badge, telemetry toggle, screen share, camera flip, and exit/minimize buttons.
class StageTopBar extends StatelessWidget {
  final ForumVideoStreamService videoService;
  final int sessionDurationSeconds;
  final String Function(int) formatDuration;
  final bool showTelemetryOverlay;
  final bool isHost;
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
    required this.sessionDurationSeconds,
    required this.formatDuration,
    required this.showTelemetryOverlay,
    this.isHost = false,
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
              // MIC TOGGLE BUTTON
              IconButton(
                icon: Icon(
                  isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: !isHost
                      ? Colors.white24
                      : (isMicMuted ? Colors.redAccent : Colors.white70),
                  size: 20,
                ),
                onPressed: !isHost ? null : onToggleMic,
                tooltip: isMicMuted ? 'Unmute Mic' : 'Mute Mic',
              ),

              // CAMERA TOGGLE BUTTON
              IconButton(
                icon: Icon(
                  isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                  color: !isHost
                      ? Colors.white24
                      : (isCameraOn ? Colors.white70 : Colors.redAccent),
                  size: 20,
                ),
                onPressed: !isHost ? null : onToggleCamera,
                tooltip: isCameraOn ? 'Turn Camera Off' : 'Turn Camera On',
              ),

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
                  color: !isHost
                      ? Colors.white24
                      : (isFrontCamera ? Colors.white70 : context.accentColor),
                  size: 20,
                ),
                onPressed: !isHost ? null : onFlipCamera,
                tooltip: 'Flip Camera',
              ),

              // TELEMETRY TOGGLE BUTTON
              InkWell(
                onTap: onToggleTelemetry,
                onLongPress: onShowTelemetryModal,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: showTelemetryOverlay ? context.accentColor : Colors.black.withValues(alpha: 0.65),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Icon(
                    Icons.analytics_rounded,
                    size: 16,
                    color: showTelemetryOverlay ? Colors.black : Colors.white70,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // COMBINED LIVE & SPECTATOR COUNT BADGE
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
              ),
            ],
          ),
        ],
      ),
    );
  }
}
