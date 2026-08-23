import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import '../services/forum_video_stream_service.dart';

class GuestThumbnailStrip extends StatelessWidget {
  final List<StreamParticipant> participants;
  final String pinnedId;
  final bool isHost;
  final StageLayoutMode layoutMode;
  final ValueChanged<String> onPinSpeaker;
  final VoidCallback? onAddStageSpeaker;
  final VoidCallback? onToggleLayout;

  const GuestThumbnailStrip({
    super.key,
    required this.participants,
    required this.pinnedId,
    required this.isHost,
    required this.layoutMode,
    required this.onPinSpeaker,
    this.onAddStageSpeaker,
    this.onToggleLayout,
  });

  IconData _getLayoutIcon(StageLayoutMode mode) {
    switch (mode) {
      case StageLayoutMode.focus:
        return Icons.crop_square_rounded;
      case StageLayoutMode.grid:
        return Icons.grid_view_rounded;
      case StageLayoutMode.presentation:
        return Icons.space_dashboard_rounded;
    }
  }

  String _getLayoutName(StageLayoutMode mode) {
    switch (mode) {
      case StageLayoutMode.focus:
        return 'Focus';
      case StageLayoutMode.grid:
        return 'Grid';
      case StageLayoutMode.presentation:
        return 'Present';
    }
  }

  void _showAllSpeakersModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121418),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.people_alt_rounded, color: context.accentColor, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Stage Participants (${participants.length})',
                    style: AppTypography.interTight(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: participants.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                  itemBuilder: (context, index) {
                    final p = participants[index];
                    final isPinned = p.id == pinnedId;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: isPinned ? context.accentColor : const Color(0xFF2C313C),
                        child: Text(
                          p.name.substring(0, 1).toUpperCase(),
                          style: AppTypography.interTight(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            p.name,
                            style: AppTypography.interTight(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          if (p.isHost) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: context.accentColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Host',
                                style: AppTypography.interTight(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: context.accentColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            p.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                            color: p.isMicMuted ? Colors.redAccent : context.accentColor,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isPinned ? context.accentColor : Colors.white12,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              onPinSpeaker(p.id);
                              Navigator.of(context).pop();
                            },
                            icon: Icon(
                              isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                              size: 14,
                            ),
                            label: Text(
                              isPinned ? 'Stage Main' : 'Pin Stage',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: Row(
        children: [
          // 1. PINNED FAR-LEFT LAYOUT CONTROL TILE (Toggles layout mode)
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 8.0),
            child: InkWell(
              onTap: onToggleLayout,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 68,
                height: 98,
                decoration: BoxDecoration(
                  color: const Color(0xFF161920).withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.accentColor.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: context.accentColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getLayoutIcon(layoutMode),
                        color: context.accentColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _getLayoutName(layoutMode),
                      style: AppTypography.interTight(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. DYNAMIC AUTO-FIT GUEST SPEAKERS (Option B: Fits maximum full tiles based on available width)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const double tileWidth = 76.0;
                const double tileSpacing = 10.0;
                const double totalTileWidth = tileWidth + tileSpacing;
                final double availableWidth = constraints.maxWidth;

                final double totalRequiredWidth = participants.length * totalTileWidth;

                int visibleCount;
                bool hasExcess;
                int excessCount;

                if (totalRequiredWidth <= availableWidth) {
                  // All participants fit cleanly without needing "+X More"
                  visibleCount = participants.length;
                  hasExcess = false;
                  excessCount = 0;
                } else {
                  // Calculate exact max full tiles that fit alongside the "+X More" tile
                  final int maxFit = ((availableWidth - totalTileWidth) / totalTileWidth)
                      .floor()
                      .clamp(1, participants.length);
                  visibleCount = maxFit;
                  hasExcess = participants.length > visibleCount;
                  excessCount = participants.length - visibleCount;
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(right: isHost ? 8.0 : 16.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...List.generate(visibleCount, (index) {
                        final p = participants[index];
                        final isPinned = p.id == pinnedId;

                        return Padding(
                          padding: const EdgeInsets.only(right: tileSpacing),
                          child: InkWell(
                            onTap: () => onPinSpeaker(p.id),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: tileWidth,
                              height: 98,
                              decoration: BoxDecoration(
                                color: const Color(0xFF121418),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isPinned ? context.accentColor : Colors.white12,
                                  width: isPinned ? 2 : 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Container(
                                        color: const Color(0xFF1A1D24),
                                        child: Center(
                                          child: CircleAvatar(
                                            radius: 18,
                                            backgroundColor: isPinned
                                                ? context.accentColor
                                                : const Color(0xFF2C313C),
                                            child: Text(
                                              p.name.substring(0, 1).toUpperCase(),
                                              style: AppTypography.interTight(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.65),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          p.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                                          color: p.isMicMuted ? Colors.redAccent : context.accentColor,
                                          size: 10,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                        color: Colors.black.withValues(alpha: 0.75),
                                        child: Text(
                                          p.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: AppTypography.interTight(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),

                      // DYNAMIC EXCESS "MORE" TILE
                      if (hasExcess)
                        Padding(
                          padding: const EdgeInsets.only(right: tileSpacing),
                          child: InkWell(
                            onTap: () => _showAllSpeakersModal(context),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: tileWidth,
                              height: 98,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B1E26),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: context.accentColor.withValues(alpha: 0.6),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: context.accentColor.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.group_rounded,
                                      color: context.accentColor,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '+$excessCount More',
                                    style: AppTypography.interTight(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'View all',
                                    style: AppTypography.interTight(
                                      fontSize: 9,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),

          // 3. PINNED FAR-RIGHT ADD SPEAKER TILE (For host)
          if (isHost)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: InkWell(
                onTap: onAddStageSpeaker,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 76,
                  height: 98,
                  decoration: BoxDecoration(
                    color: const Color(0xFF161920).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24, width: 1.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: context.accentColor.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.person_add_alt_1_rounded,
                          color: context.accentColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Add Speaker',
                        style: AppTypography.interTight(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
