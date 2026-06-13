import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/delete_account_dialog.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _sendingResetEmail = false;

  Future<void> _handlePasswordReset(String email) async {
    setState(() => _sendingResetEmail = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset link sent to $email'),
            backgroundColor: context.accentColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toFriendlyMessage()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingResetEmail = false);
    }
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => DeleteAccountDialog(
        onDelete: () => context.read<ProfileCubit>().deleteAccount(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'No email linked';
    final emailVerified = user?.emailConfirmedAt != null;

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Account & Security',
          style: AppTypography.interTight(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: BlocBuilder<ProfileCubit, ProfileState>(
        builder: (context, state) {
          if (state is ProfileLoading || state is ProfileInitial) {
            return Center(
              child: CircularProgressIndicator(color: context.accentColor),
            );
          }

          if (state is ProfileError) {
            return Center(
              child: Text(
                'Error: ${state.message}',
                style: const TextStyle(color: Colors.white),
              ),
            );
          }

          final profile = (state as ProfileLoaded).profile;
          final accountRef = profile.accountReference ?? 'Resolving...';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('Identity & ID'),
                _buildSettingTile(
                  title: 'Account Reference',
                  subtitle: accountRef,
                  icon: Icons.badge_outlined,
                  onTap: () {
                    if (profile.accountReference != null) {
                      Clipboard.setData(ClipboardData(text: profile.accountReference!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Account reference copied to clipboard')),
                      );
                    }
                  },
                  trailing: const Icon(Icons.copy_rounded, color: Colors.white24, size: 20),
                ),
                _buildSettingTile(
                  title: 'Unique User ID (UUID)',
                  subtitle: profile.id,
                  icon: Icons.fingerprint_rounded,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: profile.id));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('User ID copied to clipboard')),
                    );
                  },
                  trailing: const Icon(Icons.copy_rounded, color: Colors.white24, size: 20),
                ),
                const SizedBox(height: 32),
                _buildSectionHeader('Security & Login'),
                _buildSettingTile(
                  title: 'Primary Email',
                  subtitle: email,
                  icon: Icons.mail_outline_rounded,
                  onTap: () {},
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: emailVerified
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      emailVerified ? 'VERIFIED' : 'UNVERIFIED',
                      style: AppTypography.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: emailVerified ? Colors.greenAccent : Colors.amberAccent,
                      ),
                    ),
                  ),
                ),
                _buildSettingTile(
                  title: 'Reset Password',
                  subtitle: 'Send reset link to your email',
                  icon: Icons.lock_reset_rounded,
                  onTap: _sendingResetEmail ? () {} : () => _handlePasswordReset(email),
                  trailing: _sendingResetEmail
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.accentColor,
                          ),
                        )
                      : const Icon(Icons.chevron_right_rounded, color: Colors.white24),
                ),
                const SizedBox(height: 48),
                _buildSectionHeader('Danger Zone'),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
                  ),
                  child: ListTile(
                    onTap: () => _showDeleteConfirmation(context),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22),
                    ),
                    title: Text(
                      'Delete Account',
                      style: AppTypography.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                    subtitle: Text(
                      'Permanently remove all your data',
                      style: AppTypography.inter(fontSize: 13, color: Colors.white54),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.redAccent),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.inter(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: context.accentColor,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    required Widget trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        title: Text(
          title,
          style: AppTypography.inter(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.inter(fontSize: 13, color: Colors.white54),
        ),
        trailing: trailing,
      ),
    );
  }
}
