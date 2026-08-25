import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import '../../services/stream_service.dart';

/// Stage layout mode picker pill (Focus, Grid, Deck).
class StageModeSelector extends StatelessWidget {
  final ForumVideoStreamService videoService;

  const StageModeSelector({
    super.key,
    required this.videoService,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StageLayoutMode>(
      valueListenable: videoService.stageLayoutNotifier,
      builder: (context, layoutMode, _) {
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModeOption(
                context,
                label: 'Focus',
                icon: Icons.person_rounded,
                mode: StageLayoutMode.focus,
                currentMode: layoutMode,
              ),
              const SizedBox(width: 2),
              _buildModeOption(
                context,
                label: 'Grid',
                icon: Icons.grid_view_rounded,
                mode: StageLayoutMode.grid,
                currentMode: layoutMode,
              ),
              const SizedBox(width: 2),
              _buildModeOption(
                context,
                label: 'Deck',
                icon: Icons.present_to_all_rounded,
                mode: StageLayoutMode.presentation,
                currentMode: layoutMode,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeOption(
    BuildContext context, {
    required String label,
    required IconData icon,
    required StageLayoutMode mode,
    required StageLayoutMode currentMode,
  }) {
    final isSelected = mode == currentMode;
    return InkWell(
      onTap: () => videoService.setStageLayout(mode),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? context.accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.black : Colors.white60,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.interTight(
                fontSize: 11,
                color: isSelected ? Colors.black : Colors.white60,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
