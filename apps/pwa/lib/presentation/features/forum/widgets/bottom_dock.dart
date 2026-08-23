import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

class BottomDock extends StatelessWidget {
  final bool isScreenSharing;
  final bool isMicMuted;
  final bool isCameraOn;
  final bool isFrontCamera;
  final bool isDisabled;
  final bool isLeaveRoom;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onFlipCamera;
  final VoidCallback onEndCall;

  const BottomDock({
    super.key,
    required this.isScreenSharing,
    required this.isMicMuted,
    required this.isCameraOn,
    required this.isFrontCamera,
    this.isDisabled = false,
    this.isLeaveRoom = false,
    required this.onToggleScreenShare,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onFlipCamera,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F1115),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF161920).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Position 1: Share Screen
                IconButton(
                  icon: Icon(
                    isScreenSharing
                        ? Icons.stop_screen_share_rounded
                        : Icons.screen_share_rounded,
                    color: isDisabled
                        ? Colors.white24
                        : (isScreenSharing ? context.accentColor : Colors.white),
                  ),
                  onPressed: isDisabled ? null : onToggleScreenShare,
                  tooltip: isDisabled
                      ? 'Controls Disabled'
                      : (isScreenSharing ? 'Stop Screen Share' : 'Share Screen'),
                ),

                // Position 2: Mic Toggle
                IconButton(
                  icon: Icon(
                    isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: isDisabled
                        ? Colors.white24
                        : (isMicMuted ? Colors.redAccent : Colors.white),
                  ),
                  onPressed: isDisabled ? null : onToggleMic,
                  tooltip: isDisabled
                      ? 'Controls Disabled'
                      : (isMicMuted ? 'Unmute Mic' : 'Mute Mic'),
                ),

                // Position 3 (DEAD CENTER): End Call / Leave Room Button
                Tooltip(
                  message: isLeaveRoom ? 'Leave Room' : 'End Call',
                  child: InkWell(
                    onTap: onEndCall,
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isLeaveRoom ? Colors.redAccent.shade700 : Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isLeaveRoom ? Icons.logout_rounded : Icons.call_end_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),

                // Position 4: Camera Toggle
                IconButton(
                  icon: Icon(
                    isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                    color: isDisabled
                        ? Colors.white24
                        : (isCameraOn ? Colors.white : Colors.redAccent),
                  ),
                  onPressed: isDisabled ? null : onToggleCamera,
                  tooltip: isDisabled
                      ? 'Controls Disabled'
                      : (isCameraOn ? 'Turn Camera Off' : 'Turn Camera On'),
                ),

                // Position 5: Flip Camera
                IconButton(
                  icon: Icon(
                    Icons.flip_camera_ios_rounded,
                    color: isDisabled
                        ? Colors.white24
                        : (isFrontCamera ? Colors.white : context.accentColor),
                  ),
                  onPressed: isDisabled ? null : onFlipCamera,
                  tooltip: isDisabled ? 'Controls Disabled' : 'Flip Camera',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
