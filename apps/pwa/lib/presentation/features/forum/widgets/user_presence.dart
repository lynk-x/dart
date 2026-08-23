import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'action_bar.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

class UserPresenceCard extends StatefulWidget {
  final String userId;
  final String username;
  final String? roleId;
  final bool isOnline;
  final bool isPrimary;
  final bool isOrganizer;
  final bool isPremium;

  final bool? isMicMuted;
  final bool? isCameraOn;

  const UserPresenceCard({
    super.key,
    required this.userId,
    required this.username,
    required this.isOnline,
    this.roleId,
    this.isPrimary = false,
    this.isOrganizer = false,
    this.isPremium = false,
    this.isMicMuted,
    this.isCameraOn,
  });

  static const Map<String, String> _roleLabels = {
    'organizer': 'Organizer',
    'moderator': 'Moderator',
    'vip_member': 'VIP Member',
    'member': 'Member',
  };

  String get roleLabel => _roleLabels[roleId] ?? 'Member';

  bool get isTargetModerator => isOrganizer ? false : roleId == 'moderator';

  @override
  State<UserPresenceCard> createState() => _UserPresenceCardState();
}

class _UserPresenceCardState extends State<UserPresenceCard> {
  bool _showActions = false;

  void _toggleActions() {
    setState(() {
      _showActions = !_showActions;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.isOnline ? 1.0 : 0.45,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _toggleActions,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: widget.isPrimary
                    ? context.accentColor
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      widget.isPremium ? AppColors.secondary : Colors.white12,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.username,
                          style: AppTypography.interTight(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: widget.isPrimary ? Colors.black : Colors.white,
                          ),
                        ),
                        Text(
                          widget.roleLabel,
                          style: AppTypography.inter(
                            fontSize: 12,
                            color: widget.isPrimary
                                ? Colors.black.withValues(alpha: 0.7)
                                : Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.isMicMuted != null || widget.isCameraOn != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.isMicMuted != null) ...[
                          Icon(
                            widget.isMicMuted! ? Icons.mic_off_rounded : Icons.mic_rounded,
                            color: widget.isMicMuted!
                                ? Colors.redAccent
                                : (widget.isPrimary ? Colors.black87 : context.accentColor),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (widget.isCameraOn != null)
                          Icon(
                            widget.isCameraOn! ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                            color: widget.isCameraOn!
                                ? (widget.isPrimary ? Colors.black87 : context.accentColor)
                                : Colors.redAccent,
                            size: 16,
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (_showActions) _buildActionRow(),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    final forumCubit = context.read<ForumCubit>();
    final forumState = forumCubit.state;
    final bool canScan = forumState.isOrganizer || forumState.isModerator;

    final bool targetIsOrganizer = widget.isOrganizer;
    final bool targetIsModerator = widget.isTargetModerator;
    final bool canMute =
        !widget.isPrimary && !targetIsOrganizer && !targetIsModerator;
    final bool canMakeAdmin =
        !widget.isPrimary && !targetIsOrganizer && !targetIsModerator;
    final bool canReport = !widget.isPrimary && !targetIsOrganizer;

    return ActionBar(
      padding: const EdgeInsets.only(bottom: 12),
      items: [
        if (widget.isPrimary) ...[
          ActionBarItem(
            label: 'Edit Profile',
            onTap: () {
              _toggleActions();
              context.push('/edit-profile');
            },
            color: context.accentColor,
          ),
          // Organizers/moderators run the event rather than attend it, so a
          // ticket to scan into their own event isn't applicable to them.
          if (!canScan)
            ActionBarItem(
              label: 'View Ticket',
              onTap: () {
                _toggleActions();
                context.push('/tickets');
              },
              color: context.accentColor,
            ),
          if (canScan)
            ActionBarItem(
              label: 'Scan Tickets',
              onTap: () {
                _toggleActions();
                final eventId = forumState.eventId;
                final eventCreatedAt = forumState.eventCreatedAt;
                if (eventId == null || eventCreatedAt == null) {
                  AppSnackBars.showInfo(
                      context, 'No active event associated with this forum.');
                  return;
                }
                context.push(
                  '/forum/${forumCubit.forumReference}/scanner?eventId=$eventId&eventCreatedAt=${eventCreatedAt.toIso8601String()}',
                );
              },
              color: context.accentColor,
            ),
        ],
        if (!widget.isPrimary)
          ActionBarItem(
            label: 'Wave 👋',
            onTap: () {
              // Wave + snackbar first (both synchronous/fire-and-forget
              final cubit = context.read<ForumCubit>();
              cubit.waveAtUser(widget.userId, cubit.userName);
              AppSnackBars.showSuccess(
                  context, 'You waved at ${widget.username}!');
              Navigator.of(context).pop();
            },
          ),
        if (forumState.isOrganizer && canMakeAdmin)
          ActionBarItem(
            label: 'Make Admin',
            onTap: () async {
              _toggleActions();
              final success =
                  await context.read<ForumCubit>().makeModerator(widget.userId);
              if (!mounted) return;
              if (success) {
                AppSnackBars.showSuccess(
                    context, '${widget.username} is now an admin.');
              } else {
                AppSnackBars.showError(
                    context, 'Could not make ${widget.username} an admin.');
              }
            },
            color: context.accentColor,
          ),
        if (forumState.isModerator && canMute)
          ActionBarItem(
            label: 'Mute',
            onTap: () async {
              _toggleActions();
              final success =
                  await context.read<ForumCubit>().muteUser(widget.userId);
              if (!mounted) return;
              if (success) {
                AppSnackBars.showSuccess(
                    context, '${widget.username} has been muted.');
              } else {
                AppSnackBars.showError(
                    context, 'Could not mute ${widget.username}.');
              }
            },
            color: Colors.red,
          ),
        if (canReport) ...[
          ActionBarItem(
            label: 'Report',
            color: Colors.red,
            onTap: () {
              _toggleActions();
              _showReportModal(context);
            },
          ),
        ],
      ],
    );
  }

  void _showReportModal(BuildContext context) {
    final forumCubit = context.read<ForumCubit>();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report ${widget.username}',
                style: AppTypography.interTight(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              ...['Spam', 'Harassment', 'Inappropriate Content'].map((reason) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    reason,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    forumCubit.reportUser(widget.userId, reason);
                    Navigator.pop(bottomSheetContext);
                    AppSnackBars.showSuccess(context, 'User reported.');
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
