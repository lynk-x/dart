import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'action_bar.dart';

class UserPresenceCard extends StatefulWidget {
  final String userId;
  final String username;
  final String status;
  final bool isPrimary;
  final bool isOrganizer;
  final bool isPremium;

  const UserPresenceCard({
    super.key,
    required this.userId,
    required this.username,
    required this.status,
    this.isPrimary = false,
    this.isOrganizer = false,
    this.isPremium = false,
  });

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
    return Column(
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
                  : const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.isPremium ? AppColors.primary : Colors.white12,
              ),
            ),
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
                  widget.status,
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
        ),
        if (_showActions) _buildActionRow(),
      ],
    );
  }

  Widget _buildActionRow() {
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
        ],

        if (!widget.isPrimary)
          ActionBarItem(
            label: 'Wave 👋',
            onTap: () {
              _toggleActions();
              final cubit = context.read<ForumCubit>();
              cubit.waveAtUser(widget.userId, cubit.userName);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('You waved at ${widget.username}!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          
        if (context.read<ForumCubit>().state.isOrganizer &&
            !widget.isPrimary) ...[
          ActionBarItem(
            label: 'Make Admin',
            onTap: () {
              _toggleActions();
              context.read<ForumCubit>().makeModerator(widget.userId);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${widget.username} is now an admin.')),
              );
            },
            color: context.accentColor,
          ),
          ActionBarItem(
            label: 'Mute',
            onTap: () {
              _toggleActions();
              context.read<ForumCubit>().muteUser(widget.userId);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${widget.username} has been muted.')),
              );
            },
            color: Colors.red,
          ),
        ],

        if (!widget.isPrimary) ...[
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
    final messenger = ScaffoldMessenger.of(context);

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
                    messenger.showSnackBar(
                      const SnackBar(content: Text('User reported.')),
                    );
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
