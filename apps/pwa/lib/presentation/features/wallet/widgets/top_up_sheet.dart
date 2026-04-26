import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';

import 'package:lynk_x/presentation/features/wallet/cubit/wallet_cubit.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_state.dart';
import 'package:lynk_x/presentation/features/wallet/models/wallet_model.dart';

class TopUpSheet extends StatefulWidget {
  final List<WalletBalance> currentBalances;
  const TopUpSheet({super.key, required this.currentBalances});

  @override
  State<TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<TopUpSheet> {
  static const _mpesaCurrencies = {'KES', 'UGX', 'TZS', 'NGN'};
  static const _quickAmounts = {
    'KES': [500.0, 1000.0, 2500.0, 5000.0],
    'UGX': [20000.0, 50000.0, 100000.0, 200000.0],
    'TZS': [20000.0, 50000.0, 100000.0, 250000.0],
    'NGN': [5000.0, 10000.0, 25000.0, 50000.0],
    'USD': [10.0, 25.0, 50.0, 100.0],
    'GBP': [10.0, 25.0, 50.0, 100.0],
  };

  final _amountController = TextEditingController();
  final _phoneController  = TextEditingController();
  String _currency = 'KES';
  double? _quickPick;

  @override
  void dispose() {
    _amountController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool get _isMpesa => _mpesaCurrencies.contains(_currency);

  double? get _parsedAmount {
    final raw = _amountController.text.trim();
    return raw.isEmpty ? _quickPick : double.tryParse(raw);
  }

  void _onQuickPick(double v) {
    setState(() {
      _quickPick = v;
      _amountController.clear();
    });
  }

  void _submit() {
    final amount = _parsedAmount;
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }
    final cubit = context.read<WalletCubit>();
    if (_isMpesa) {
      final phone = _phoneController.text.trim();
      if (phone.length < 9) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid phone number')),
        );
        return;
      }
      cubit.initiateTopUpMpesa(
        amount: amount,
        currency: _currency,
        phone: '+254${phone.replaceFirst(RegExp(r'^0'), '')}',
      );
    } else {
      cubit.initiateTopUpCard(amount: amount, currency: _currency);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WalletCubit, WalletState>(
      // Close the sheet as soon as the balance increases after STK was sent
      listenWhen: (prev, curr) {
        if (curr.topUpStatus != TopUpStatus.waitingMpesa) return false;
        for (final cb in curr.balances) {
          final pb = widget.currentBalances.cast<WalletBalance?>()
              .firstWhere((b) => b?.currency == cb.currency, orElse: () => null);
          if (pb != null && cb.balance > pb.balance) return true;
        }
        return false;
      },
      listener: (ctx, _) => Navigator.pop(ctx),
      builder: (context, state) {
        final isWaiting  = state.topUpStatus == TopUpStatus.waitingMpesa;
        final isSubmitting = state.topUpStatus == TopUpStatus.submitting;

        return AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              24, 20, 24,
              MediaQuery.of(context).viewInsets.bottom + 32,
            ),
            decoration: BoxDecoration(
              color: AppColors.tertiary,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: isWaiting ? _buildWaiting(state) : _buildForm(state, isSubmitting),
          ),
        );
      },
    );
  }

  // ── Waiting state (post-STK) ───────────────────────────────────────────────

  Widget _buildWaiting(WalletState state) {
    final amount = _parsedAmount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _handle(),
        const SizedBox(height: 28),
        const CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 24),
        Text('Waiting for M-Pesa...',
            style: AppTypography.inter(
                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 8),
        Text(
          'An STK push was sent to your phone.\nEnter your M-Pesa PIN to confirm.',
          textAlign: TextAlign.center,
          style: AppTypography.inter(fontSize: 14, color: Colors.white54),
        ),
        if (amount != null) ...[
          const SizedBox(height: 16),
          Text(
            '$_currency ${amount.toStringAsFixed(0)}',
            style: AppTypography.inter(
                fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
        ],
        const SizedBox(height: 28),
        TextButton(
          onPressed: () => context.read<WalletCubit>().resetTopUp(),
          child: const Text('Cancel',
              style: TextStyle(color: Colors.white38, fontSize: 14)),
        ),
      ],
    );
  }

  // ── Input form ─────────────────────────────────────────────────────────────

  Widget _buildForm(WalletState state, bool isSubmitting) {
    final picks = _quickAmounts[_currency] ?? _quickAmounts['USD']!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _handle(),
        const SizedBox(height: 16),

        Text('Top Up Wallet',
            style: AppTypography.inter(
                fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 20),

        // ── Currency selector ──────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['KES', 'UGX', 'TZS', 'NGN', 'USD', 'GBP'].map((c) {
              final selected = c == _currency;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _currency = c;
                    _quickPick = null;
                    _amountController.clear();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.5)
                            : Colors.white12,
                      ),
                    ),
                    child: Text(c,
                        style: TextStyle(
                            color: selected ? AppColors.primary : Colors.white54,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),

        // ── Quick-pick amounts ─────────────────────────────────────────
        Row(
          children: picks.map((v) {
            final selected = _quickPick == v && _amountController.text.isEmpty;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _onQuickPick(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.5)
                            : Colors.white12,
                      ),
                    ),
                    child: Text(
                      v >= 1000
                          ? '${(v / 1000).toStringAsFixed(0)}K'
                          : v.toStringAsFixed(0),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: selected ? AppColors.primary : Colors.white60,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),

        // ── Custom amount input ────────────────────────────────────────
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          onChanged: (_) => setState(() => _quickPick = null),
          decoration: InputDecoration(
            hintText: 'Or enter amount',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            suffixText: _currency,
            suffixStyle: TextStyle(color: AppColors.primary),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),

        // ── M-Pesa phone input ─────────────────────────────────────────
        if (_isMpesa) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: '07XXXXXXXX',
              hintStyle:
                  TextStyle(color: Colors.white.withValues(alpha: 0.3)),
              prefixText: '+254  ',
              prefixStyle: const TextStyle(color: Colors.white60),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ],

        // ── Error ──────────────────────────────────────────────────────
        if (state.topUpStatus == TopUpStatus.error &&
            state.topUpError != null) ...[
          const SizedBox(height: 10),
          Text(state.topUpError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
        ],

        const SizedBox(height: 20),

        // ── CTA ────────────────────────────────────────────────────────
        PrimaryButton(
          text: _isMpesa ? 'Send STK Push' : 'Continue to Payment',
          isLoading: isSubmitting,
          onPressed: isSubmitting ? null : _submit,
        ),
      ],
    );
  }

  Widget _handle() => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        ),
      );
}
