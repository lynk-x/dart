import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_cubit.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_state.dart';
import 'package:go_router/go_router.dart';

class WalletSecurityGate extends StatefulWidget {
  final Widget child;
  const WalletSecurityGate({super.key, required this.child});

  @override
  State<WalletSecurityGate> createState() => _WalletSecurityGateState();
}

class _WalletSecurityGateState extends State<WalletSecurityGate> {
  final List<int> _pin = [];
  bool _isError = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    
    // Auto-trigger biometrics if enabled in settings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final state = context.read<WalletCubit>().state;
        if (state.useBiometrics && state.hasPinSet && !state.isWalletUnlocked) {
          context.read<WalletCubit>().unlockWithBiometrics();
        }
      }
    });
  }

  @override
  void dispose() {
    // Lock the wallet immediately when leaving the wallet feature.
    // We capture the cubit reference now because context will be invalid in the microtask.
    final cubit = context.read<WalletCubit>();
    Future.microtask(() => cubit.lockWallet());
    
    _focusNode.dispose();
    super.dispose();
  }

  void _onNumberTap(int n) {
    if (_pin.length < 6) {
      setState(() {
        _pin.add(n);
        _isError = false;
      });
      if (_pin.length == 6) {
        _verifyPin();
      }
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() => _pin.removeLast());
    }
  }

  Future<void> _verifyPin() async {
    final pinStr = _pin.join();
    final success = await context.read<WalletCubit>().unlockWithPin(pinStr);
    if (!success) {
      setState(() {
        _pin.clear();
        _isError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WalletCubit, WalletState>(
      builder: (context, state) {
        if (!state.hasPinSet) return widget.child;
        if (state.isWalletUnlocked) return widget.child;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            context.go('/');
          },
          child: Scaffold(
            backgroundColor: AppColors.primaryBackground,
            body: KeyboardListener(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: (event) {
                if (event is KeyDownEvent) {
                  final key = event.logicalKey;
                  if (key.keyLabel.length == 1 && RegExp(r'[0-9]').hasMatch(key.keyLabel)) {
                    _onNumberTap(int.parse(key.keyLabel));
                  } else if (key == LogicalKeyboardKey.backspace) {
                    _onDelete();
                  }
                }
              },
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: SafeArea(
                    child: Column(
                      children: [
                        const Spacer(),
                        const Icon(Icons.lock_outline, color: AppColors.primary, size: 48),
                        const SizedBox(height: 24),
                        Text(
                          'Wallet Locked',
                          style: AppTypography.inter(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isError ? 'Incorrect PIN. Try again.' : 'Enter your 6-digit PIN to continue',
                          style: AppTypography.inter(fontSize: 14, color: _isError ? Colors.redAccent : Colors.white54),
                        ),
                        const SizedBox(height: 40),
                        
                        // ── PIN Indicators ──────────────────────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(6, (index) {
                            final isFilled = index < _pin.length;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isFilled ? AppColors.primary : Colors.white10,
                                border: Border.all(color: isFilled ? AppColors.primary : Colors.white24),
                              ),
                            );
                          }),
                        ),

                        const Spacer(),

                        // ── Number Pad ──────────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                          child: GridView.count(
                            shrinkWrap: true,
                            crossAxisCount: 3,
                            mainAxisSpacing: 20,
                            crossAxisSpacing: 20,
                            children: [
                              ...List.generate(9, (index) => _PinButton(n: index + 1, onTap: () => _onNumberTap(index + 1))),
                               if (state.useBiometrics)
                                 IconButton(
                                   onPressed: () => context.read<WalletCubit>().unlockWithBiometrics(),
                                   icon: const Icon(Icons.fingerprint, color: Colors.white70, size: 32),
                                 )
                               else
                                 const SizedBox.shrink(),
                              _PinButton(n: 0, onTap: () => _onNumberTap(0)),
                              IconButton(
                                onPressed: _onDelete,
                                icon: const Icon(Icons.backspace_outlined, color: Colors.white70, size: 24),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PinButton extends StatelessWidget {
  final int n;
  final VoidCallback onTap;
  const _PinButton({required this.n, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: Text(
          n.toString(),
          style: AppTypography.inter(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }
}
