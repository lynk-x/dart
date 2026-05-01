import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';

import 'package:lynk_x/presentation/features/wallet/cubit/wallet_cubit.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_state.dart';
import 'package:lynk_x/presentation/features/wallet/models/wallet_model.dart';

class TransferSheet extends StatefulWidget {
  final String recipientAccountId;
  final List<WalletBalance> currentBalances;

  const TransferSheet({
    super.key,
    required this.recipientAccountId,
    required this.currentBalances,
  });

  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet> {
  final _amountController = TextEditingController();
  late String _currency;
  double? _quickPick;

  @override
  void initState() {
    super.initState();
    // Default to the first currency with balance, or KES
    _currency = widget.currentBalances.isNotEmpty 
        ? widget.currentBalances.first.currency 
        : 'KES';
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

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

    final balance = widget.currentBalances.cast<WalletBalance?>()
        .firstWhere((b) => b?.currency == _currency, orElse: () => null);
    
    if (balance == null || balance.balance < amount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insufficient balance')),
      );
      return;
    }

    context.read<WalletCubit>().transferFunds(
      amount: amount,
      currency: _currency,
      recipientAccountId: widget.recipientAccountId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WalletCubit, WalletState>(
      listener: (context, state) {
        if (state.withdrawStatus == WithdrawStatus.success) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transfer successful!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      },
      builder: (context, state) {
        final isSubmitting = state.withdrawStatus == WithdrawStatus.submitting;

        return AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              24, 20, 24,
              MediaQuery.of(context).viewInsets.bottom + 32,
            ),
            decoration: BoxDecoration(
              color: AppColors.tertiary,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _handle(),
                const SizedBox(height: 16),
                Text('Send Funds',
                    style: AppTypography.inter(
                        fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                Text(
                  'To: ${widget.recipientAccountId}',
                  style: AppTypography.inter(fontSize: 12, color: Colors.white38),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),

                // ── Currency selector ──────────────────────────────────────────
                if (widget.currentBalances.length > 1)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: widget.currentBalances.map((b) {
                        final selected = b.currency == _currency;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _currency = b.currency;
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
                              child: Text(b.currency,
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
                  children: [100.0, 500.0, 1000.0, 2000.0].map((v) {
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
                    hintText: 'Enter amount',
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

                // ── Error ──────────────────────────────────────────────────────
                if (state.withdrawStatus == WithdrawStatus.error &&
                    state.withdrawError != null) ...[
                  const SizedBox(height: 10),
                  Text(state.withdrawError!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],

                const SizedBox(height: 24),

                // ── CTA ────────────────────────────────────────────────────────
                PrimaryButton(
                  text: 'Transfer Funds',
                  isLoading: isSubmitting,
                  onPressed: isSubmitting ? null : _submit,
                ),
              ],
            ),
          ),
        );
      },
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
