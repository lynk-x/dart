import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

class BottomDock extends StatelessWidget {
  final bool isScreenSharing;
  final bool isMicMuted;
  final bool isCameraOn;
  final bool isFrontCamera;
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
    required this.onToggleScreenShare,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onFlipCamera,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                  color: isScreenSharing ? context.accentColor : Colors.white,
                ),
                onPressed: onToggleScreenShare,
                tooltip: isScreenSharing ? 'Stop Screen Share' : 'Share Screen',
              ),

              // Position 2: Mic Toggle
              IconButton(
                icon: Icon(
                  isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: isMicMuted ? Colors.redAccent : Colors.white,
                ),
                onPressed: onToggleMic,
                tooltip: isMicMuted ? 'Unmute Mic' : 'Mute Mic',
              ),

              // Position 3 (DEAD CENTER): Red End Call Button
              InkWell(
                onTap: onEndCall,
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_end_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),

              // Position 4: Camera Toggle
              IconButton(
                icon: Icon(
                  isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                  color: isCameraOn ? Colors.white : Colors.redAccent,
                ),
                onPressed: onToggleCamera,
                tooltip: isCameraOn ? 'Turn Camera Off' : 'Turn Camera On',
              ),

              // Position 5: Flip Camera
              IconButton(
                icon: Icon(
                  Icons.flip_camera_ios_rounded,
                  color: isFrontCamera ? Colors.white : context.accentColor,
                ),
                onPressed: onFlipCamera,
                tooltip: 'Flip Camera',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
