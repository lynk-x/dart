import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_cubit.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_state.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynk_x/presentation/features/wallet/widgets/wallet_pin_setup_sheet.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  @override
  void initState() {
    super.initState();
    context.read<WalletCubit>().init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOptIn();
    });
  }

  Future<void> _checkOptIn() async {
    final prefs = await SharedPreferences.getInstance();
    final hasOptedIn = prefs.getBool('wallet_opt_in_v1') ?? false;
    if (!hasOptedIn && mounted) {
      _showOptInPopup();
    }
  }

  void _showOptInPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.secondaryBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Welcome to Lynk-X Wallet',
          style: AppTypography.inter(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        content: Text(
          'Manage your funds, pay for tickets, and transfer money to friends seamlessly. By continuing, you agree to enable wallet features.',
          style: AppTypography.inter(fontSize: 14, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('wallet_opt_in_v1', true);
              if (context.mounted) {
                Navigator.pop(context);
                _showPinSetup();
              }
            },
            child: Text(
              'Get Started',
              style: AppTypography.inter(fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _showPinSetup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const WalletPinSetupSheet(),
    );
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
          'Wallet Dashboard',
          style: AppTypography.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: BlocBuilder<WalletCubit, WalletState>(
        builder: (context, state) {
          if (state.isLoading && state.accountId == null) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          final accountId = state.accountId ?? 'No account linked';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                // ── QR Code Section ──────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryBackground,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'My QR Code',
                        style: AppTypography.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Scan to transfer funds',
                        style: AppTypography.inter(fontSize: 13, color: Colors.white54),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: BarcodeWidget(
                          barcode: Barcode.qrCode(),
                          data: accountId,
                          width: 220,
                          height: 220,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SelectableText(
                        accountId,
                        style: AppTypography.inter(fontSize: 12, color: Colors.white38, letterSpacing: 1),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),

                // ── Navigation Cards ─────────────────────────────────────────
                _DashboardActionCard(
                  title: 'My Wallets',
                  subtitle: 'View balances and add new currencies',
                  icon: Icons.account_balance_wallet_rounded,
                  onTap: () => context.push('/wallet/list'),
                ),
                
                const SizedBox(height: 16),
                
                _DashboardActionCard(
                  title: 'Transaction History',
                  subtitle: 'View all recent P2P and top-up activity',
                  icon: Icons.history_rounded,
                  onTap: () {
                    context.push('/wallet/list');
                  },
                ),
                
                const SizedBox(height: 40),
                Text(
                  'Powered by Lynk-X Pay',
                  style: AppTypography.inter(fontSize: 12, color: Colors.white24, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DashboardActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _DashboardActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.secondaryBackground,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: AppColors.primary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTypography.inter(fontSize: 13, color: Colors.white54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}
