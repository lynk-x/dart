import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/l10n/app_localizations.dart';
import '../services/forum_video_stream_service.dart';
import 'forum_skeletons.dart';
import 'media_device_selector_sheet.dart';
import 'user_presence.dart';

/// The end-drawer component for the Forum screen.
///
/// Displays the list of online members (using [UserPresenceCard]) and a
/// persistent bottom section for event progress and global settings.
class PresenceDrawer extends StatelessWidget {
  /// The current progress of the forum's active event (0.0 to 1.0).
  final double eventProgress;

  /// Full forum roster (from `ForumState.members`) — every member,
  /// regardless of whether they're currently online.
  final List<Map<String, dynamic>> members;

  /// List of online users extracted from Supabase Presence.
  final List<Map<String, dynamic>> onlineUsers;

  final bool isPremium;
  final bool isOrganizer;
  final String? eventId;
  final String forumId;
  final DateTime? eventCreatedAt;
  final VoidCallback? onEventProgressTap;
  final bool isLoading;

  const PresenceDrawer({
    super.key,
    required this.eventProgress,
    required this.members,
    required this.onlineUsers,
    required this.isPremium,
    required this.isOrganizer,
    required this.forumId,
    required this.isLoading,
    this.eventId,
    this.eventCreatedAt,
    this.onEventProgressTap,
  });

  /// Merges the full member roster with live presence, keyed by user id.
  /// Presence values (name, organizer flag) win when a member is online
  /// since they're the freshest source; members not currently present are
  /// kept with isOnline: false rather than dropped. Presence entries with
  /// no matching member row (e.g. a guest session) are appended too, so
  /// nobody visible in presence disappears. Sorted online-first, then
  /// alphabetically within each group.
  List<Map<String, dynamic>> _mergedRoster() {
    final onlineById = <String, Map<String, dynamic>>{};
    for (final u in onlineUsers) {
      final id = (u['user_id'] ?? u['id'] ?? '').toString();
      if (id.isNotEmpty) onlineById[id] = u;
    }

    final seen = <String>{};
    final merged = <Map<String, dynamic>>[];

    for (final m in members) {
      final id = (m['id'] ?? '').toString();
      if (id.isEmpty) continue;
      seen.add(id);
      final online = onlineById[id];
      merged.add({
        'id': id,
        'user_name':
            online?['user_name'] ?? online?['full_name'] ?? m['user_name'],
        // Presence never carries role_id, only a coarse is_organizer flag —
        // fall back to the roster's role_id (the only source with the full
        // organizer/moderator/vip_member/member distinction).
        'role_id': m['role_id'],
        'is_organizer': online?['is_organizer'] ?? m['is_organizer'] == true,
        'is_premium': m['is_premium'] == true,
        'is_online': online != null,
      });
    }

    for (final u in onlineUsers) {
      final id = (u['user_id'] ?? u['id'] ?? '').toString();
      if (id.isEmpty || seen.contains(id)) continue;
      merged.add({
        'id': id,
        'user_name': u['user_name'] ?? u['full_name'] ?? 'Unknown',
        'role_id': u['is_organizer'] == true ? 'organizer' : null,
        'is_organizer': u['is_organizer'] == true,
        'is_premium': u['is_premium'] == true,
        'is_online': true,
      });
    }

    merged.sort((a, b) {
      if (a['is_online'] != b['is_online']) {
        return a['is_online'] == true ? -1 : 1;
      }
      return (a['user_name'] as String)
          .toLowerCase()
          .compareTo((b['user_name'] as String).toLowerCase());
    });

    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final roster = _mergedRoster();
    return Drawer(
      width: (MediaQuery.of(context).size.width * 0.85).clamp(280, 320),
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(topLeft: Radius.circular(40))),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
                width: 60,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 36),
                  Text(
                    'MEMBERS (${roster.length})',
                    style: AppTypography.interTight(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 20),
                    tooltip: 'Settings',
                    onPressed: () => showMediaDeviceSelectorSheet(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SkeletonFade(
                child: isLoading
                    ? const SkeletonPresenceList(key: ValueKey('skeleton'))
                    : ValueListenableBuilder<bool>(
                        valueListenable: ForumVideoStreamService().isLiveNotifier,
                        builder: (context, isVideoLive, _) {
                          return ValueListenableBuilder<List<StreamParticipant>>(
                            valueListenable: ForumVideoStreamService().activeParticipantsNotifier,
                            builder: (context, participants, _) {
                              return ListView.builder(
                                key: const ValueKey('content'),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: roster.length,
                                itemBuilder: (context, index) {
                                  try {
                                    final user = roster[index];
                                    final String userId = user['id'].toString();
                                    if (userId.isEmpty) return const SizedBox.shrink();

                                    final match = participants.firstWhere(
                                      (p) =>
                                          p.id == userId ||
                                          (p.isHost &&
                                              p.id == 'host' &&
                                              userId ==
                                                  Supabase.instance.client.auth
                                                      .currentUser?.id),
                                      orElse: () => const StreamParticipant(
                                          id: '', name: '', role: ''),
                                    );

                                    final bool isStreamActive = match.id.isNotEmpty;

                                    return UserPresenceCard(
                                      key: ValueKey('presence_$userId'),
                                      userId: userId,
                                      username:
                                          (user['user_name'] ?? 'Unknown').toString(),
                                      roleId: user['role_id'] as String?,
                                      isOnline: user['is_online'] == true,
                                      isOrganizer: user['is_organizer'] == true,
                                      isPremium: user['is_premium'] == true,
                                      showCameraControl: isVideoLive,
                                      isPrimary: userId ==
                                          Supabase.instance.client.auth.currentUser?.id,
                                      isMicMuted: isStreamActive ? match.isMicMuted : null,
                                      isCameraOn: isStreamActive ? match.isCameraOn : null,
                                      onToggleMic: (id) => ForumVideoStreamService().toggleParticipantMic(id),
                                      onToggleCamera: (id) => ForumVideoStreamService().toggleParticipantCamera(id),
                                    );
                                  } catch (e) {
                                    debugPrint(
                                        '[PresenceDrawer] Error building user card: $e');
                                    return const SizedBox.shrink();
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),
              ),
            ),
            // Persistent Bottom Section
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () {
                      if (eventId == null || eventId!.isEmpty) return;
                      Navigator.of(context).pop();
                      onEventProgressTap?.call();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                  (l10n?.eventProgress ?? 'Event Progress')
                                      .toUpperCase(),
                                  style: AppTypography.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white54)),
                              const Icon(Icons.chevron_right,
                                  color: Colors.white24, size: 16),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: eventProgress,
                              backgroundColor: Colors.white10,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  context.accentColor),
                              minHeight: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
