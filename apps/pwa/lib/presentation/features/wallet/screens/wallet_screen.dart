import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_cubit.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_state.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lynk_x/presentation/features/wallet/widgets/wallet_pin_setup_sheet.dart';
import 'package:lynk_x/presentation/features/wallet/widgets/transfer_sheet.dart';
import 'package:intl/intl.dart';

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
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Welcome to Lynk-X Wallet',
          style: AppTypography.inter(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        content: Text(
          'Manage your funds, pay for tickets and transfer money to friends seamlessly. By continuing, you agree to enable wallet features.',
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

  void _showScanner(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) => const _WalletScannerSheet(),
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
          'Wallet',
          style: AppTypography.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () => context.push('/wallet/settings'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: BlocBuilder<WalletCubit, WalletState>(
        builder: (context, state) {
          if (state.isLoading && state.accountId == null) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          final accountId = state.accountId ?? 'No account linked';

          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 950) {
                return _buildDesktopLayout(state, accountId);
              }
              return _buildMobileLayout(state, accountId);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showScanner(context),
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.black),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppColors.surface,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Container(height: 20),
      ),
    );
  }

  Widget _buildMobileLayout(WalletState state, String accountId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          _QRCard(accountId: accountId),
          const SizedBox(height: 32),
          _QuickActionsRow(),
          const SizedBox(height: 32),
          // In mobile, we might still want a peek at wallets or history if space allows
          // but keeping it simple for now as per current mobile design.
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(WalletState state, String accountId) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        padding: const EdgeInsets.all(32),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: QR Code & Quick Actions
            SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _QRCard(accountId: accountId),
                    const SizedBox(height: 32),
                    _DesktopQuickActionsGrid(),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 40),
            // Right Column: Wallets & Recent Activity
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('Your Wallets'),
                    const SizedBox(height: 16),
                    _WalletsGrid(state: state),
                    const SizedBox(height: 48),
                    _buildSectionHeader('Recent Activity'),
                    const SizedBox(height: 16),
                    _RecentActivityList(state: state),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: AppTypography.inter(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
    );
  }
}

class _QRCard extends StatelessWidget {
  final String accountId;
  const _QRCard({required this.accountId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: QrImageView(
              data: accountId,
              version: QrVersions.auto,
              size: 200.0,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.circle,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SelectableText(
            accountId,
            style: AppTypography.inter(fontSize: 10, color: Colors.white38, letterSpacing: 1),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ActionIcon(
          label: 'Send',
          icon: Icons.send_rounded,
          onTap: () => context.push('/wallet/list'),
        ),
        _ActionIcon(
          label: 'Receive',
          icon: Icons.download_rounded,
          onTap: () => context.push('/wallet/list'),
        ),
        const SizedBox(width: 60), // Space for centered FAB
        _ActionIcon(
          label: 'Wallets',
          icon: Icons.account_balance_wallet_rounded,
          onTap: () => context.push('/wallet/list'),
        ),
        _ActionIcon(
          label: 'History',
          icon: Icons.history_rounded,
          onTap: () => context.push('/wallet/history'),
        ),
      ],
    );
  }
}

class _DesktopQuickActionsGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: AppTypography.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
          ),
          const SizedBox(height: 24),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.2,
            children: [
              _DesktopActionCard(
                label: 'Send Money',
                icon: Icons.send_rounded,
                onTap: () => context.push('/wallet/list'),
              ),
              _DesktopActionCard(
                label: 'Request',
                icon: Icons.download_rounded,
                onTap: () => context.push('/wallet/list'),
              ),
              _DesktopActionCard(
                label: 'All Wallets',
                icon: Icons.account_balance_wallet_rounded,
                onTap: () => context.push('/wallet/list'),
              ),
              _DesktopActionCard(
                label: 'Activity',
                icon: Icons.history_rounded,
                onTap: () => context.push('/wallet/history'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopActionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _DesktopActionCard({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTypography.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletsGrid extends StatelessWidget {
  final WalletState state;
  const _WalletsGrid({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.balances.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(child: Text('No active wallets', style: TextStyle(color: Colors.white54))),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: 100,
      ),
      itemCount: state.balances.length,
      itemBuilder: (context, index) {
        final balance = state.balances[index];
        return InkWell(
          onTap: () => context.push('/wallet/list/${balance.currency}'),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.account_balance_wallet, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(balance.currency, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text(
                        state.isPrivacyModeEnabled 
                          ? '•••••• ${balance.currency}'
                          : '${balance.balance.toStringAsFixed(2)} ${balance.currency}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentActivityList extends StatelessWidget {
  final WalletState state;
  const _RecentActivityList({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.transactions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(child: Text('No recent activity', style: TextStyle(color: Colors.white54))),
      );
    }

    final recent = state.transactions.take(5).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: recent.length,
        separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
        itemBuilder: (context, index) {
          final tx = recent[index];
          final isCredit = tx.amount > 0;
          
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: (isCredit ? Colors.green : Colors.red).withValues(alpha: 0.1),
              child: Icon(
                isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                color: isCredit ? Colors.green : Colors.red,
                size: 18,
              ),
            ),
            title: Text(tx.reason, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
              DateFormat('MMM dd, HH:mm').format(tx.createdAt),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            trailing: Text(
              state.isPrivacyModeEnabled
                ? '••••••'
                : '${isCredit ? '+' : ''}${tx.amount.toStringAsFixed(2)} ${tx.currency}',
              style: TextStyle(
                color: isCredit ? Colors.green : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionIcon({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTypography.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _WalletScannerSheet extends StatelessWidget {
  const _WalletScannerSheet();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final String? code = barcodes.first.rawValue;
                      if (code != null) {
                        Navigator.pop(context);
                        
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (sheetContext) => BlocProvider.value(
                            value: context.read<WalletCubit>(),
                            child: TransferSheet(
                              recipientAccountId: code,
                              currentBalances: context.read<WalletCubit>().state.balances,
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
                Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 2),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      'Scan a Lynk-X QR Code',
                      style: AppTypography.inter(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
