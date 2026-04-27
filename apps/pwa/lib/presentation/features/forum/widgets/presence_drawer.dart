import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final bool showAds;
  final ValueChanged<bool> onAdsChanged;

  const PresenceDrawer({
    super.key,
    required this.eventProgress,
    required this.onlineUsers,
    required this.isPremium,
    required this.showAds,
    required this.onAdsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
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
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: onlineUsers.map((user) {
                  return UserPresenceCard(
                    userId: user['user_id'] as String? ?? '',
                    username: user['user_name'] as String? ?? 'Unknown',
                    status: user['status'] as String? ?? 'Online',
                    isOrganizer: user['is_organizer'] == true,
                    isPremium: user['is_premium'] == true,
                    isPrimary: user['user_id'] ==
                        Supabase.instance.client.auth.currentUser?.id,
                  );
                }).toList(),
              ),
            ),
            // Persistent Bottom Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('EVENT PROGRESS',
                      style: AppTypography.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white54)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: eventProgress,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SizedBox(height: 10),
                  if (isPremium)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Enable Advertisements',
                            style: AppTypography.inter(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        Switch(
                          value: showAds,
                          onChanged: onAdsChanged,
                          activeThumbColor: AppColors.primary,
                        ),
                      ],
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
