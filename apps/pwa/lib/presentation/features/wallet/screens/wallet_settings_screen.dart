import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/wallet/widgets/wallet_pin_setup_sheet.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lynk_x/presentation/shared/widgets/permission_request_sheet.dart';
import '../cubit/wallet_cubit.dart';
import '../cubit/wallet_state.dart';

class WalletSettingsPage extends StatefulWidget {
  const WalletSettingsPage({super.key});

  @override
  State<WalletSettingsPage> createState() => _WalletSettingsPageState();
}

class _WalletSettingsPageState extends State<WalletSettingsPage> {
  final LocalAuthentication auth = LocalAuthentication();
  bool _canCheckBiometrics = false;
  String _biometricLabel = 'Biometric Unlock';

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final canCheck = await auth.canCheckBiometrics || await auth.isDeviceSupported();
    final available = await auth.getAvailableBiometrics();

    String label = 'Biometric Unlock';
    if (available.contains(BiometricType.face)) {
      label = 'Face ID Unlock';
    } else if (available.contains(BiometricType.fingerprint)) {
      label = 'Fingerprint Unlock';
    } else if (available.contains(BiometricType.iris)) {
      label = 'Iris Unlock';
    }
    
    setState(() {
      _canCheckBiometrics = canCheck;
      _biometricLabel = label;
    });
  }

  Future<void> _toggleBiometrics(bool value) async {
    if (value) {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final hasAcknowledged = prefs.getBool('biometric_permission_acknowledged') ?? false;

      if (!hasAcknowledged) {
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => PermissionRequestSheet(
            title: 'Secure with Biometrics',
            description: 'Use your fingerprint or face to quickly and securely unlock your wallet and authorize transfers.',
            icon: Icons.fingerprint_rounded,
            actionLabel: 'Enable Biometrics',
            onGranted: () async {
              await prefs.setBool('biometric_permission_acknowledged', true);
              if (context.mounted) {
                _actuallyToggleBiometrics(true);
              }
            },
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    _actuallyToggleBiometrics(value);
  }

  Future<void> _actuallyToggleBiometrics(bool value) async {
    // If enabling, verify with biometrics first to ensure it works
    if (value) {
      try {
        final didAuth = await auth.authenticate(
          localizedReason: 'Confirm biometrics for wallet access',
          options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
        );
        if (!didAuth) return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification failed: ${e.toString()}')),
          );
        }
        return;
      }
    }

    if (!mounted) return;
    context.read<WalletCubit>().toggleBiometrics(value);
  }

  String _getDailyLimit(String? tier) {
    switch (tier) {
      case 'tier_2_verified':
        return '\$10,000.00';
      case 'tier_3_advanced':
        return '\$50,000.00';
      default:
        return '\$1,000.00';
    }
  }

  String _getKycTierLabel(String? tier) {
    switch (tier) {
      case 'tier_2_verified':
        return 'Tier 2 (Verified)';
      case 'tier_3_advanced':
        return 'Tier 3 (Advanced)';
      default:
        return 'Tier 1 (Basic)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WalletCubit, WalletState>(
      builder: (context, state) {
        final currentLimit = _getDailyLimit(state.kycTier);
        final kycLabel = _getKycTierLabel(state.kycTier);
        final isFullyVerified = state.kycTier == 'tier_3_advanced';

        return Scaffold(
          backgroundColor: AppColors.primaryBackground,
          appBar: AppBar(
            backgroundColor: AppColors.primaryBackground,
            elevation: 0,
            centerTitle: true,
            title: Text(
              'Wallet Settings',
              style: AppTypography.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('Accounts'),
                _buildSettingTile(
                  title: 'Linked Accounts',
                  subtitle: 'Manage external bank or card links',
                  icon: Icons.link_rounded,
                  onTap: () {},
                ),

                const SizedBox(height: 32),
                _buildSectionHeader('Verification & Limits'),
                _buildSettingTile(
                  title: 'Daily Transfer Limit',
                  subtitle: 'Current limit: $currentLimit',
                  icon: Icons.speed_rounded,
                  onTap: isFullyVerified ? () {} : () => context.push('/kyc'),
                  trailing: isFullyVerified 
                    ? null 
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'INCREASE',
                          style: AppTypography.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ),
                ),
                _buildSettingTile(
                  title: 'KYC Status',
                  subtitle: kycLabel,
                  icon: Icons.verified_user_outlined,
                  onTap: () => context.push('/kyc'),
                ),

                const SizedBox(height: 32),
                _buildSectionHeader('Security'),
                _buildSettingTile(
                  title: 'Change Wallet PIN',
                  subtitle: 'Update your 6-digit security code',
                  icon: Icons.lock_outline_rounded,
                  onTap: () => _showChangePin(),
                ),
                _buildBiometricTile(state),
                
                const SizedBox(height: 32),
                _buildSectionHeader('Privacy'),
                _buildSwitchTile(
                  title: 'Privacy Mode',
                  subtitle: 'Hide balances on the main dashboard',
                  icon: Icons.visibility_off_outlined,
                  value: state.isPrivacyModeEnabled,
                  onChanged: (val) => context.read<WalletCubit>().togglePrivacyMode(val),
                ),

                const SizedBox(height: 40),
                Center(
                  child: Text(
                    'Wallet Version 1.0.4',
                    style: AppTypography.inter(fontSize: 12, color: Colors.white24),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBiometricTile(WalletState state) {
    if (!_canCheckBiometrics) {
      return _buildSettingTile(
        title: 'Biometrics Unavailable',
        subtitle: 'Your device or browser doesn\'t support biometric unlock.',
        icon: Icons.fingerprint_rounded,
        onTap: () {},
        trailing: const Icon(Icons.info_outline, color: Colors.white24, size: 20),
      );
    }

    return _buildSwitchTile(
      title: _biometricLabel,
      subtitle: 'Unlock your wallet using your device biometrics',
      icon: Icons.fingerprint_rounded,
      value: state.useBiometrics,
      onChanged: _toggleBiometrics,
    );
  }

  void _showChangePin() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const WalletPinSetupSheet(), // Reusing setup sheet for change
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: 1),
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Widget? trailing,
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
        title: Text(title, style: AppTypography.inter(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        subtitle: Text(subtitle, style: AppTypography.inter(fontSize: 13, color: Colors.white54)),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: Colors.white24),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        title: Text(title, style: AppTypography.inter(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        subtitle: Text(subtitle, style: AppTypography.inter(fontSize: 13, color: Colors.white54)),
        trailing: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeTrackColor: AppColors.primary,
        ),
      ),
    );
  }
}
