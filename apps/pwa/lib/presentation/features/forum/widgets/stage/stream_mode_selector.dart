import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import '../../services/stream_service.dart';

/// Compact stage layout mode picker & media control bar (Focus, Grid, Deck + Mic & Camera toggles).
class StageModeSelector extends StatefulWidget {
  final ForumVideoStreamService videoService;
  final VoidCallback? onToggleMic;
  final VoidCallback? onToggleCamera;

  const StageModeSelector({
    super.key,
    required this.videoService,
    this.onToggleMic,
    this.onToggleCamera,
  });

  @override
  State<StageModeSelector> createState() => _StageModeSelectorState();
}

class _StageModeSelectorState extends State<StageModeSelector> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StageLayoutMode>(
      valueListenable: widget.videoService.stageLayoutNotifier,
      builder: (context, layoutMode, _) {
        final isMicMuted = widget.videoService.isMicMuted;
        final isCameraOn = widget.videoService.isCameraOn;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Minimized mode switcher buttons (Icon-only with Tooltip)
              _buildCompactModeOption(
                context,
                tooltip: 'Focus Mode',
                icon: Icons.person_rounded,
                mode: StageLayoutMode.focus,
                currentMode: layoutMode,
              ),
              const SizedBox(width: 2),
              _buildCompactModeOption(
                context,
                tooltip: 'Grid Mode',
                icon: Icons.grid_view_rounded,
                mode: StageLayoutMode.grid,
                currentMode: layoutMode,
              ),
              const SizedBox(width: 2),
              _buildCompactModeOption(
                context,
                tooltip: 'Deck / Presentation',
                icon: Icons.present_to_all_rounded,
                mode: StageLayoutMode.presentation,
                currentMode: layoutMode,
              ),

              // Vertical Divider
              Container(
                height: 16,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: Colors.white24,
              ),

              // Mic Toggle Button
              InkWell(
                onTap: () {
                  if (widget.onToggleMic != null) {
                    widget.onToggleMic!();
                  } else {
                    final next = !widget.videoService.isMicMuted;
                    widget.videoService.isMicMuted = next;
                    widget.videoService.toggleMic(!next);
                  }
                  setState(() {});
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    size: 15,
                    color: isMicMuted ? Colors.redAccent : context.accentColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // Video / Camera Toggle Button
              InkWell(
                onTap: () {
                  if (widget.onToggleCamera != null) {
                    widget.onToggleCamera!();
                  } else {
                    final next = !widget.videoService.isCameraOn;
                    widget.videoService.isCameraOn = next;
                    widget.videoService.toggleCamera(next);
                  }
                  setState(() {});
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                    size: 15,
                    color: isCameraOn ? context.accentColor : Colors.redAccent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactModeOption(
    BuildContext context, {
    required String tooltip,
    required IconData icon,
    required StageLayoutMode mode,
    required StageLayoutMode currentMode,
  }) {
    final isSelected = mode == currentMode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => widget.videoService.setStageLayout(mode),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: isSelected ? context.accentColor : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 14,
            color: isSelected ? Colors.black : Colors.white60,
          ),
        ),
      ),
    );
  }
}
