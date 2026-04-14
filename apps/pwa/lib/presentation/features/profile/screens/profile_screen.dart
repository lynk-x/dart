import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_core/core.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lynk_x/services/push_notification_service.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  void _shareProfile() {
    Share.share(
      'Check out Lynk-X - The ultimate event platform! Join me at: https://lynk-x.app',
      subject: 'Join me on Lynk-X!',
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ProfileCubit()..loadProfile(),
      child: Scaffold(
        backgroundColor: AppColors.primaryBackground,
        appBar: AppBar(
          backgroundColor: AppColors.primaryBackground,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 28, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          title: Image.asset(
            'assets/images/lynk-x_combined-logo.png',
            width: 200,
            fit: BoxFit.contain,
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 24, color: Colors.white),
              onPressed: _shareProfile,
            ),
          ],
        ),
        body: BlocBuilder<ProfileCubit, ProfileState>(
          builder: (context, state) {
            if (state is ProfileLoading) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF00FF00)),
              );
            }

            if (state is ProfileError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.white.withValues(alpha: 0.4)),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load profile',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => context.read<ProfileCubit>().loadProfile(),
                      child: const Text('Retry', style: TextStyle(color: Color(0xFF00FF00))),
                    ),
                  ],
                ),
              );
            }

            if (state is ProfileLoaded) {
              return _ProfileContent(profile: state.profile);
            }

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  final ProfileModel profile;

  const _ProfileContent({required this.profile});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          // Avatar
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 56,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  backgroundImage: profile.avatarUrl != null
                      ? CachedNetworkImageProvider(profile.avatarUrl!)
                      : null,
                  child: profile.avatarUrl == null
                      ? Text(
                          _initials(profile.fullName ?? profile.userName),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                if (profile.verificationStatus == 'verified')
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF00FF00),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 16, color: Colors.black),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Name
          Text(
            profile.fullName ?? 'Anonymous',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '@${profile.userName}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 15,
            ),
          ),

          // Tagline
          if (profile.tagline != null && profile.tagline!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              profile.tagline!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],

          // Tier badge — tappable to upgrade when on free tier
          const SizedBox(height: 16),
          GestureDetector(
            onTap: profile.subscriptionTier != 'pro'
                ? () => context.push('/upgrade')
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: profile.subscriptionTier == 'pro'
                    ? const Color(0xFF00FF00).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: profile.subscriptionTier == 'pro'
                      ? const Color(0xFF00FF00).withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile.subscriptionTier == 'pro' ? 'Premium Member' : 'Free Tier',
                    style: TextStyle(
                      color: profile.subscriptionTier == 'pro'
                          ? const Color(0xFF00FF00)
                          : Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (profile.subscriptionTier != 'pro') ...[
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_upward, size: 14,
                        color: Colors.white.withValues(alpha: 0.4)),
                  ],
                ],
              ),
            ),
          ),

          // Bio
          if (profile.bio != null && profile.bio!.isNotEmpty) ...[
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.bio!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 28),

          // Actions
          _ActionTile(
            icon: Icons.edit_outlined,
            label: 'Edit Profile',
            onTap: () => context.push('/edit-profile'),
          ),
          _ActionTile(
            icon: Icons.wallet_outlined,
            label: 'My Wallet',
            onTap: () => context.push('/wallet'),
          ),
          _ActionTile(
            icon: Icons.confirmation_number_outlined,
            label: 'My Tickets',
            onTap: () => context.push('/tickets'),
          ),
          _ActionTile(
            icon: Icons.verified_user_outlined,
            label: 'Identity Verification',
            subtitle: 'Opens web dashboard',
            onTap: () => context.push('/kyc'),
          ),
          _ActionTile(
            icon: Icons.feedback_outlined,
            label: 'Send Feedback',
            onTap: () => context.push('/feedback'),
          ),
          _ActionTile(
            icon: Icons.logout,
            label: 'Sign Out',
            isDestructive: true,
            onTap: () async {
              await PushNotificationService.instance.removeToken();
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) context.go('/auth');
            },
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return '?';
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ActionTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.redAccent : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color.withValues(alpha: 0.7), size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: TextStyle(
                            color: color.withValues(alpha: 0.4),
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color.withValues(alpha: 0.3), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
