import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_cubit.dart';

class WalletPinSetupSheet extends StatefulWidget {
  const WalletPinSetupSheet({super.key});

  @override
  State<WalletPinSetupSheet> createState() => _WalletPinSetupSheetState();
}

class _WalletPinSetupSheetState extends State<WalletPinSetupSheet> {
  final List<int> _pin1 = [];
  final List<int> _pin2 = [];
  bool _isConfirming = false;
  String? _error;

  void _onNumberTap(int n) {
    setState(() => _error = null);
    final target = _isConfirming ? _pin2 : _pin1;
    if (target.length < 6) {
      setState(() => target.add(n));
      if (target.length == 6) {
        if (!_isConfirming) {
          setState(() => _isConfirming = true);
        } else {
          _finalize();
        }
      }
    }
  }

  void _onDelete() {
    final target = _isConfirming ? _pin2 : _pin1;
    if (target.isNotEmpty) {
      setState(() => target.removeLast());
    } else if (_isConfirming) {
      setState(() => _isConfirming = false);
    }
  }

  void _finalize() {
    if (_pin1.join() == _pin2.join()) {
      context.read<WalletCubit>().setWalletPin(_pin1.join());
      Navigator.pop(context);
    } else {
      setState(() {
        _pin2.clear();
        _error = 'PINs do not match. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryBackground,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),
            Text(
              _isConfirming ? 'Confirm your PIN' : 'Set your Wallet PIN',
              style: AppTypography.inter(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? (_isConfirming ? 'Re-enter the 6-digit code' : 'Choose a secure 6-digit code'),
              style: AppTypography.inter(fontSize: 14, color: _error != null ? Colors.redAccent : Colors.white54),
            ),
            const SizedBox(height: 40),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final target = _isConfirming ? _pin2 : _pin1;
                final isFilled = index < target.length;
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

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                children: [
                  ...List.generate(9, (index) => _PinButton(n: index + 1, onTap: () => _onNumberTap(index + 1))),
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
