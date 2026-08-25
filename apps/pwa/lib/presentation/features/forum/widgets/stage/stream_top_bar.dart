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
  final VoidCallback onToggleTelemetry;
  final VoidCallback onShowTelemetryModal;
  final VoidCallback onMinimize;
  final VoidCallback? onToggleScreenShare;
  final VoidCallback? onFlipCamera;

  const StageTopBar({
    super.key,
    required this.videoService,
    required this.sessionDurationSeconds,
    required this.formatDuration,
    required this.showTelemetryOverlay,
    this.isHost = false,
    this.isScreenSharing = false,
    this.isFrontCamera = true,
    required this.onToggleTelemetry,
    required this.onShowTelemetryModal,
    required this.onMinimize,
    this.onToggleScreenShare,
    this.onFlipCamera,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Row(
        children: [
          // MINIMIZE / LEAVE BUTTON
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
          const SizedBox(width: 8),

          // LIVE INDICATOR & DURATION
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
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'LIVE',
                  style: AppTypography.interTight(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatDuration(sessionDurationSeconds),
                  style: AppTypography.interTight(
                    fontSize: 11,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // SPECTATOR COUNT BADGE
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

          const Spacer(),

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
        ],
      ),
    );
  }
}
