import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import '../services/forum_video_stream_service.dart';

/// Google Meet-style Right Sidebar for Desktop live stream participant management.
class ParticipantSidebar extends StatelessWidget {
  final List<StreamParticipant> participants;
  final String pinnedId;
  final bool isHost;
  final bool isStageLocked;
  final ValueChanged<String> onPinSpeaker;
  final ValueChanged<String>? onToggleMic;
  final ValueChanged<String>? onToggleCamera;
  final ValueChanged<String>? onToggleStage;
  final VoidCallback? onAddStageSpeaker;
  final VoidCallback? onToggleStageLock;
  final VoidCallback? onMuteAll;
  final VoidCallback? onClose;

  const ParticipantSidebar({
    super.key,
    required this.participants,
    required this.pinnedId,
    required this.isHost,
    required this.onPinSpeaker,
    this.isStageLocked = false,
    this.onToggleMic,
    this.onToggleCamera,
    this.onToggleStage,
    this.onAddStageSpeaker,
    this.onToggleStageLock,
    this.onMuteAll,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: Color(0xFF14171D),
        border: Border(
          left: BorderSide(color: Colors.white12, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. HEADER (Google Meet Style)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
            child: Row(
              children: [
                Icon(Icons.people_alt_rounded, color: context.accentColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'People (${participants.length})',
                  style: AppTypography.interTight(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                    onPressed: onClose,
                    tooltip: 'Close sidebar',
                  ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // 2. HOST ACTIONS (Add Co-host & Moderation Bar)
          if (isHost)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: onAddStageSpeaker,
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                      label: Text(
                        'Add Co-host',
                        style: AppTypography.interTight(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: isStageLocked
                                ? Colors.amber.shade900.withValues(alpha: 0.3)
                                : Colors.transparent,
                            side: BorderSide(
                              color: isStageLocked ? Colors.amberAccent : Colors.white24,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: onToggleStageLock,
                          icon: Icon(
                            isStageLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                            size: 14,
                            color: isStageLocked ? Colors.amberAccent : Colors.white70,
                          ),
                          label: Text(
                            isStageLocked ? 'Locked' : 'Lock Unmute',
                            style: AppTypography.interTight(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isStageLocked ? Colors.amberAccent : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: onMuteAll,
                          icon: const Icon(Icons.mic_off_rounded, size: 14, color: Colors.redAccent),
                          label: Text(
                            'Mute All',
                            style: AppTypography.interTight(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          if (isHost) const Divider(color: Colors.white10, height: 1),

          // 3. PARTICIPANTS LIST
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: participants.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1, indent: 56),
              itemBuilder: (context, index) {
                final p = participants[index];
                final isPinned = p.id == pinnedId;

                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Stack(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: isPinned ? context.accentColor : Colors.grey.shade800,
                        child: Text(
                          p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                          style: AppTypography.interTight(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (p.isSpeaking)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: context.accentColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF14171D), width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.name,
                          style: AppTypography.interTight(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (p.isHost)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: context.accentColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'HOST',
                            style: AppTypography.interTight(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: context.accentColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    p.isOnStage ? 'On Stage' : 'Audience',
                    style: AppTypography.interTight(
                      fontSize: 11,
                      color: p.isOnStage ? Colors.greenAccent : Colors.white38,
                    ),
                  ),
                  trailing: isHost
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Pin Spotlight Button
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                              icon: Icon(
                                isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                                size: 16,
                                color: isPinned ? context.accentColor : Colors.white38,
                              ),
                              onPressed: () => onPinSpeaker(p.id),
                              tooltip: isPinned ? 'Unpin' : 'Pin Spotlight',
                            ),
                            const SizedBox(width: 4),

                            // Mic Toggle Button
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                              icon: Icon(
                                p.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                                size: 16,
                                color: p.isMicMuted ? Colors.redAccent : Colors.white70,
                              ),
                              onPressed: () => onToggleMic?.call(p.id),
                              tooltip: p.isMicMuted ? 'Unmute' : 'Mute',
                            ),
                            const SizedBox(width: 4),

                            // Camera Toggle Button
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                              icon: Icon(
                                p.isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                                size: 16,
                                color: p.isCameraOn ? Colors.white70 : Colors.redAccent,
                              ),
                              onPressed: () => onToggleCamera?.call(p.id),
                              tooltip: p.isCameraOn ? 'Turn Camera Off' : 'Turn Camera On',
                            ),
                          ],
                        )
                      : Icon(
                          p.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          size: 16,
                          color: p.isMicMuted ? Colors.redAccent : Colors.greenAccent,
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
