import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/profile/cubit/profile_cubit.dart';
import 'package:lynk_x/presentation/features/profile/cubit/profile_state.dart';

import 'package:lynk_x/l10n/app_localizations.dart';
import 'package:lynk_x/app.dart';

class HomeDrawer extends StatefulWidget {
  const HomeDrawer({super.key});

  @override
  State<HomeDrawer> createState() => _HomeDrawerState();
}

class _HomeDrawerState extends State<HomeDrawer> {
  final User? _user = Supabase.instance.client.auth.currentUser;

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        context.go('/auth');
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.logout} Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showLanguageActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.primaryBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('English',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  LynkXAppWrapper.setLocale(context, const Locale('en', ''));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Kiswahili',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  LynkXAppWrapper.setLocale(context, const Locale('sw', ''));
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Drawer(
      backgroundColor: AppColors.primaryBackground,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                BlocBuilder<ProfileCubit, ProfileState>(
                  builder: (context, state) {
                    final isUnverified =
                        _user != null && _user.emailConfirmedAt == null;

                    if (state is ProfileLoaded) {
                      final profile = state.profile;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
                        child: Column(
                          children: [
                            if (isUnverified) _buildUnverifiedBanner(),
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor: AppColors.tertiary,
                                  backgroundImage: profile.avatarUrl != null
                                      ? NetworkImage(profile.avatarUrl!)
                                      : null,
                                  child: profile.avatarUrl == null
                                      ? Text(
                                          (profile.fullName ??
                                                  profile.userName)[0]
                                              .toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primaryText,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        profile.fullName ?? profile.userName,
                                        style: AppTypography.interTight(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primaryText,
                                        ),
                                      ),
                                      Text(
                                        profile.email ??
                                            _user?.email ??
                                            'No email',
                                        style: AppTypography.inter(
                                          fontSize: 14,
                                          color: AppColors.primaryText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
                      child: Column(
                        children: [
                          if (isUnverified) _buildUnverifiedBanner(),
                          Row(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: const BoxDecoration(
                                  color: AppColors.tertiary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 120,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: Colors.white10,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      width: 180,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: Colors.white10,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.white),
                  title: Text(l10n.editProfile,
                      style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    context.pop();
                    context.push('/edit-profile');
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.confirmation_num, color: Colors.white),
                  title: const Text('My Tickets',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    context.pop();
                    context.push('/tickets');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline,
                      color: Colors.white),
                  title: Text(l10n.feedback,
                      style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    context.pop();
                    context.push('/feedback');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.language, color: Colors.white),
                  title: const Text('Language',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    _showLanguageActionSheet(context);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 24.0, top: 16.0),
            child: Column(
              children: [
                // ── Upgrade CTA Card ──
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        context.pop();
                        // Direct the user to the new standalone Web App upgrade page!
                        // In production, change localhost to lynk-x.com
                        launchUrl(Uri.parse('http://localhost:3000/upgrade'),
                            mode: LaunchMode.externalApplication);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.workspace_premium,
                                color: Colors.black, size: 32),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Go Premium',
                                    style: AppTypography.interTight(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Ad-free experience & more',
                                    style: AppTypography.inter(
                                      fontSize: 12,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios,
                                color: Colors.black54, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                ListTile(
                  title: Text(
                    l10n.logout,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  trailing: const Icon(Icons.logout, color: Colors.redAccent),
                  onTap: () async {
                    final bool? confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: AppColors.primaryBackground,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: Text(
                          l10n.logoutConfirmTitle,
                          textAlign: TextAlign.center,
                          style: AppTypography.interTight(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        content: Text(
                          l10n.logoutConfirmMessage,
                          textAlign: TextAlign.center,
                          style: AppTypography.inter(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                        actionsPadding: const EdgeInsets.all(16),
                        actions: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: Text(
                                    l10n.logout,
                                    style: AppTypography.interTight(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: Text(
                                    l10n.cancel,
                                    style: AppTypography.inter(
                                      fontSize: 16,
                                      color: Colors.white60,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      await _signOut();
                    }
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        final url = context
                            .read<SystemConfigCubit>()
                            .state
                            .getString('privacy_policy_url');
                        if (url.isNotEmpty) {
                          launchUrl(Uri.parse(url),
                              mode: LaunchMode.inAppBrowserView);
                        }
                      },
                      child: Text(
                        l10n.privacyPolicy,
                        style: const TextStyle(
                          color: AppColors.tertiary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        '·',
                        style: TextStyle(color: Colors.white24, fontSize: 12),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        final url = context
                            .read<SystemConfigCubit>()
                            .state
                            .getString('terms_conditions_url');
                        if (url.isNotEmpty) {
                          launchUrl(Uri.parse(url),
                              mode: LaunchMode.inAppBrowserView);
                        }
                      },
                      child: Text(
                        l10n.termsConditions,
                        style: const TextStyle(
                          color: AppColors.tertiary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${l10n.version} 1.0.0',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnverifiedBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.amber, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Verify your email',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
