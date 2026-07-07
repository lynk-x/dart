import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';

/// Shown when an anonymous (claimed-ticket) guest attempts a write action
/// the forum RLS policies reserve for registered users (posting, editing,
/// voting) — see `NOT identity.is_anonymous()` in social.forum_messages'
/// insert/update/delete policies. Routes into the existing profile-setup
/// flow rather than /auth, since /auth would start a fresh sign-in and
/// fork away from the anonymous session already holding this guest's
/// claimed tickets and forum membership.
class GuestProfilePromptSheet extends StatelessWidget {
  final String returnTo;

  const GuestProfilePromptSheet({super.key, required this.returnTo});

  static Future<void> show(BuildContext context, {required String returnTo}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => GuestProfilePromptSheet(returnTo: returnTo),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.accentColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_add_alt_1_rounded,
                color: context.accentColor, size: 40),
          ),
          const SizedBox(height: 24),
          Text(
            "You're viewing as a guest",
            style: AppTypography.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Create your profile to post, reply and join polls in this forum.',
            style: AppTypography.inter(
              fontSize: 14,
              color: Colors.white70,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          PrimaryButton(
            text: 'Create your profile',
            onPressed: () {
              Navigator.pop(context);
              context.push(
                  '/profile-setup?next=${Uri.encodeComponent(returnTo)}');
            },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Not now',
              style: AppTypography.inter(
                color: Colors.white38,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
