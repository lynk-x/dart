import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_x/l10n/app_localizations.dart';
import 'user_presence.dart';

/// The end-drawer component for the Forum screen.
///
/// Displays the list of online members (using [UserPresenceCard]) and a
/// persistent bottom section for event progress and global settings.
class PresenceDrawer extends StatelessWidget {
  /// The current progress of the forum's active event (0.0 to 1.0).
  final double eventProgress;

  /// List of online users extracted from Supabase Presence.
  final List<Map<String, dynamic>> onlineUsers;

  final bool isPremium;
  final bool isOrganizer;
  final String? eventId;
  final String forumId;
  final DateTime? eventCreatedAt;

  const PresenceDrawer({
    super.key,
    required this.eventProgress,
    required this.onlineUsers,
    required this.isPremium,
    required this.isOrganizer,
    required this.forumId,
    this.eventId,
    this.eventCreatedAt,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            const SizedBox(height: 20),
            Text('ONLINE (${onlineUsers.length})',
                style: AppTypography.interTight(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: onlineUsers.length,
                itemBuilder: (context, index) {
                  try {
                    final user = onlineUsers[index];
                    final String userId =
                        (user['user_id'] ?? user['id'] ?? '').toString();
                    if (userId.isEmpty) return const SizedBox.shrink();

                    return UserPresenceCard(
                      key: ValueKey('presence_$userId'),
                      userId: userId,
                      username:
                          (user['user_name'] ?? user['full_name'] ?? 'Unknown')
                              .toString(),
                      status: (user['status'] ?? 'Online').toString(),
                      isOrganizer: user['is_organizer'] == true,
                      isPremium: user['is_premium'] == true,
                      isPrimary: userId == Supabase.instance.client.auth.currentUser?.id,
                    );
                  } catch (e) {
                    debugPrint('[PresenceDrawer] Error building user card: $e');
                    return const SizedBox.shrink();
                  }
                },
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
                      if (eventId != null && eventId!.isNotEmpty) {
                        context.push(
                          '/forum/$forumId/sessions',
                          extra: {
                            'eventId': eventId,
                            'isOrganizer': isOrganizer,
                            'eventCreatedAt': eventCreatedAt,
                          },
                        );
                        Navigator.of(context).pop();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text((l10n?.eventProgress ?? 'Event Progress').toUpperCase(),
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
