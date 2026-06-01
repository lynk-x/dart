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
import 'package:lynk_x/presentation/shared/widgets/permission_request_sheet.dart';

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
              style: AppTypography.inter(fontWeight: FontWeight.bold, color: context.accentColor),
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

  void _showScanner(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasAcknowledged = prefs.getBool('camera_permission_acknowledged') ?? false;

    if (!hasAcknowledged && context.mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => PermissionRequestSheet(
          title: 'Scan QR Codes',
          description: 'To pay and transfer funds via QR, we need access to your device camera.',
          icon: Icons.camera_alt_rounded,
          actionLabel: 'Enable Camera',
          onGranted: () async {
            await prefs.setBool('camera_permission_acknowledged', true);
            if (context.mounted) {
              _actuallyShowScanner(context);
            }
          },
        ),
      );
      return;
    }
    if (!context.mounted) return;
    _actuallyShowScanner(context);
  }

  void _actuallyShowScanner(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) => const _WalletScannerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/');
      },
      child: Scaffold(
        backgroundColor: AppColors.primaryBackground,
        appBar: AppBar(
          backgroundColor: AppColors.primaryBackground,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () => context.go('/'),
          ),
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
            return Center(child: CircularProgressIndicator(color: context.accentColor));
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
        backgroundColor: context.accentColor,
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
        constraints: const BoxConstraints(maxWidth: 1000),
        padding: const EdgeInsets.all(32),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: QR Code
            SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Invisible placeholder to match the right side title height exactly
                  Text(
                    ' ',
                    style: AppTypography.inter(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ' ',
                    style: AppTypography.inter(fontSize: 14),
                  ),
                  const SizedBox(height: 32),
                  _QRCard(accountId: accountId),
                ],
              ),
            ),
            const SizedBox(width: 64),
            // Right: Quick Actions Grid (Replacing Wallets/Activity)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Actions',
                    style: AppTypography.inter(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select an action to manage your funds and view history',
                    style: AppTypography.inter(fontSize: 14, color: Colors.white54),
                  ),
                  const SizedBox(height: 32),
                  _DesktopQuickActionsGrid(),
                ],
              ),
            ),
          ],
        ),
      ),
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
          // Lanyard Hole
          Container(
            width: 64,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primaryBackground, // Matches background to look like a hole
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black38, width: 2), // Gives it depth
            ),
          ),
          const SizedBox(height: 24),
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
            child: Stack(
              alignment: Alignment.center,
              children: [
                QrImageView(
                  data: accountId,
                  version: QrVersions.auto,
                  size: 200.0,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.circle,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
                // Custom Logo Overlay with Background
                Container(
                  width: 52,
                  height: 52,
                  padding: const EdgeInsets.all(2), // Reduced padding to zoom in
                  decoration: BoxDecoration(
                    color: AppColors.primaryBackground, // Dark background
                    borderRadius: BorderRadius.circular(12), // Rounded square
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: Image.asset(
                    'assets/images/lynk-x_logo.png',
                    fit: BoxFit.contain, // Logo will now take up much more space
                  ),
                ),
              ],
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
            Icon(icon, color: context.accentColor, size: 28),
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
              color: context.accentColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: context.accentColor, size: 28),
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

class _WalletScannerSheet extends StatefulWidget {
  const _WalletScannerSheet();

  @override
  State<_WalletScannerSheet> createState() => _WalletScannerSheetState();
}

class _WalletScannerSheetState extends State<_WalletScannerSheet> {
  final MobileScannerController controller = MobileScannerController();
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    // MobileScanner handles permissions internally when starting,
    // but we can listen to the status.
    setState(() {
      _isChecking = true;
    });

    // In a real app with permission_handler, we would check here.
    // For mobile_scanner, we wait for the first frame or use the controller.
    
    setState(() {
      _isChecking = false;
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

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
            child: _isChecking 
              ? Center(child: CircularProgressIndicator(color: context.accentColor))
              : ValueListenableBuilder(
                  valueListenable: controller,
                  builder: (context, state, child) {
                    if (!state.isInitialized) {
                      return Center(child: CircularProgressIndicator(color: context.accentColor));
                    }
                    
                    if (state.error != null) {
                       return Center(
                         child: Column(
                           mainAxisSize: MainAxisSize.min,
                           children: [
                             const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                             const SizedBox(height: 16),
                             Text(
                               state.error!.errorCode == MobileScannerErrorCode.permissionDenied
                                 ? 'Camera permission denied'
                                 : 'Could not start camera',
                               style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                             ),
                             const SizedBox(height: 8),
                             const Text(
                               'Please enable camera access in settings',
                               style: TextStyle(color: Colors.white54, fontSize: 13),
                             ),
                           ],
                         ),
                       );
                    }

                    return Stack(
                      children: [
                        MobileScanner(
                          controller: controller,
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
                              border: Border.all(color: context.accentColor, width: 2),
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
                        Positioned(
                          top: 20,
                          right: 20,
                          child: IconButton(
                            icon: ValueListenableBuilder(
                              valueListenable: controller,
                              builder: (context, state, child) {
                                switch (state.torchState) {
                                  case TorchState.off:
                                    return const Icon(Icons.flash_off, color: Colors.white);
                                  case TorchState.on:
                                    return Icon(Icons.flash_on, color: context.accentColor);
                                  case TorchState.auto:
                                    return const Icon(Icons.flash_auto, color: Colors.white70);
                                  case TorchState.unavailable:
                                    return const Icon(Icons.flash_off, color: Colors.white24);
                                }
                              },
                            ),
                            onPressed: () => controller.toggleTorch(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
