import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/wallet/widgets/wallet_pin_setup_sheet.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WalletSettingsPage extends StatefulWidget {
  const WalletSettingsPage({super.key});

  @override
  State<WalletSettingsPage> createState() => _WalletSettingsPageState();
}

class _WalletSettingsPageState extends State<WalletSettingsPage> {
  final LocalAuthentication auth = LocalAuthentication();
  bool _canCheckBiometrics = false;
  bool _useBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final canCheck = await auth.canCheckBiometrics || await auth.isDeviceSupported();
    final prefs = await SharedPreferences.getInstance();
    final useBio = prefs.getBool('wallet_use_biometrics_v1') ?? false;
    
    setState(() {
      _canCheckBiometrics = canCheck;
      _useBiometrics = useBio;
    });
  }

  Future<void> _toggleBiometrics(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wallet_use_biometrics_v1', value);
    setState(() => _useBiometrics = value);
  }

  @override
  Widget build(BuildContext context) {
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
            _buildSectionHeader('Security'),
            _buildSettingTile(
              title: 'Change Wallet PIN',
              subtitle: 'Update your 6-digit security code',
              icon: Icons.lock_outline_rounded,
              onTap: () => _showChangePin(),
            ),
            if (_canCheckBiometrics)
              _buildSwitchTile(
                title: 'Biometric Unlock',
                subtitle: 'Use FaceID or Fingerprint to access wallet',
                icon: Icons.fingerprint_rounded,
                value: _useBiometrics,
                onChanged: _toggleBiometrics,
              ),
            
            const SizedBox(height: 32),
            _buildSectionHeader('Privacy'),
            _buildSwitchTile(
              title: 'Privacy Mode',
              subtitle: 'Hide balances on the main dashboard',
              icon: Icons.visibility_off_outlined,
              value: false,
              onChanged: (val) {},
            ),

            const SizedBox(height: 32),
            _buildSectionHeader('Limits & Control'),
            _buildSettingTile(
              title: 'Daily Transfer Limit',
              subtitle: 'Currently set to \$1,000.00',
              icon: Icons.speed_rounded,
              onTap: () {},
            ),
            _buildSettingTile(
              title: 'Linked Accounts',
              subtitle: 'Manage external bank or card links',
              icon: Icons.link_rounded,
              onTap: () {},
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
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24),
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
