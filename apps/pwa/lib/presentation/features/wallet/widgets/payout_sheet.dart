import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_cubit.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_state.dart';
import 'package:lynk_x/presentation/features/wallet/models/wallet_model.dart';

class PayoutSheet extends StatefulWidget {
  final List<WalletBalance> currentBalances;
  final String? initialCurrency;

  const PayoutSheet({
    super.key,
    required this.currentBalances,
    this.initialCurrency,
  });

  @override
  State<PayoutSheet> createState() => _PayoutSheetState();
}

class _PayoutSheetState extends State<PayoutSheet> {
  final _amountController = TextEditingController();
  final _phoneController  = TextEditingController();
  final _pinController    = TextEditingController();

  late String  _selectedCurrency;
  String? _selectedMethodId;
  bool    _showAddMethod    = false;

  @override
  void initState() {
    super.initState();
    _selectedCurrency = widget.initialCurrency ?? 'KES';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  double? get _selectedBalance {
    final b = widget.currentBalances.cast<WalletBalance?>().firstWhere(
      (b) => b?.currency == _selectedCurrency,
      orElse: () => null,
    );
    return b?.balance;
  }

  bool get _needsKyc {
    final tier = context.read<WalletCubit>().state.kycTier;
    return tier == null || tier == 'tier_1_basic';
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WalletCubit, WalletState>(
      listenWhen: (prev, curr) =>
          prev.withdrawStatus != curr.withdrawStatus,
      listener: (ctx, state) {
        if (state.withdrawStatus == WithdrawStatus.success) {
          Navigator.pop(ctx);
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text('Withdrawal submitted. Funds will be sent once processed.'),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final isSubmitting   = state.withdrawStatus == WithdrawStatus.submitting;
        final isAddingMethod = state.withdrawStatus == WithdrawStatus.addingMethod;

        return Container(
          padding: EdgeInsets.fromLTRB(
            20, 12, 20,
            MediaQuery.of(context).viewInsets.bottom + 32,
          ),
          decoration: BoxDecoration(
            color: AppColors.tertiary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _handle(),
                Text(
                  'Withdraw Funds',
                  style: AppTypography.inter(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Funds move to escrow and are released to your payout method.',
                  style: AppTypography.inter(fontSize: 13, color: Colors.white38),
                ),
                const SizedBox(height: 20),

                if (_needsKyc) ...[
                  _KycGateBanner(
                    onVerify: () {
                      Navigator.pop(context);
                      context.push('/kyc');
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Currency chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['KES', 'USD', 'GBP'].map((c) {
                      final selected = c == _selectedCurrency;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedCurrency = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primary.withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected ? AppColors.primary.withValues(alpha: 0.5) : Colors.white12,
                            ),
                          ),
                          child: Text(
                            c,
                            style: TextStyle(
                              color: selected ? AppColors.primary : Colors.white54,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),

                if (_selectedBalance != null)
                  Text(
                    'Available: $_selectedCurrency ${_selectedBalance!.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                const SizedBox(height: 10),

                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: const TextStyle(color: Colors.white24),
                    prefixText: '$_selectedCurrency  ',
                    prefixStyle: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  'Payout Method',
                  style: AppTypography.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white54),
                ),
                const SizedBox(height: 8),

                if (state.payoutMethods.isEmpty && !_showAddMethod)
                  _EmptyMethodCard(onAdd: () => setState(() => _showAddMethod = true))
                else ...[
                  ...state.payoutMethods.map((m) {
                    final isSelected = _selectedMethodId == m['id'];
                    final provider = m['platform_payment_providers'] as Map<String, dynamic>?;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedMethodId = m['id']),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? AppColors.primary.withValues(alpha: 0.4) : Colors.white12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.account_balance_wallet, color: isSelected ? AppColors.primary : Colors.white38, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(provider?['display_name'] ?? 'Payout Method', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                                  Text(m['provider_identity'] as String, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                                ],
                              ),
                            ),
                            if (isSelected) Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                          ],
                        ),
                      ),
                    );
                  }),
                  if (!_showAddMethod)
                    TextButton.icon(
                      onPressed: () => setState(() => _showAddMethod = true),
                      icon: const Icon(Icons.add, size: 16, color: AppColors.primary),
                      label: const Text('Add another method', style: TextStyle(color: AppColors.primary, fontSize: 13)),
                    ),
                ],

                if (_showAddMethod)
                  _AddMpesaForm(
                    controller: _phoneController,
                    isLoading: isAddingMethod,
                    onAdd: () {
                      final raw = _phoneController.text.trim();
                      if (raw.isEmpty) return;
                      final phone = raw.startsWith('+') ? raw : '+254${raw.replaceFirst(RegExp(r'^0'), '')}';
                      context.read<WalletCubit>().addPayoutMethod(
                        providerName: 'mpesa_daraja',
                        identity:     phone,
                        label:        'M-Pesa $phone',
                      );
                      setState(() => _showAddMethod = false);
                    },
                    onCancel: () => setState(() => _showAddMethod = false),
                  ),

                Text(
                   'Confirm with PIN',
                   style: AppTypography.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white54),
                 ),
                 const SizedBox(height: 8),
                 TextField(
                   controller: _pinController,
                   obscureText: true,
                   keyboardType: TextInputType.number,
                   inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                   style: const TextStyle(color: Colors.white, fontSize: 16),
                   decoration: InputDecoration(
                     hintText: 'Enter 6-digit PIN',
                     hintStyle: const TextStyle(color: Colors.white24),
                     filled: true,
                     fillColor: Colors.white.withValues(alpha: 0.05),
                     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                     contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                   ),
                 ),
                 const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    text: 'Request Withdrawal',
                    isLoading: isSubmitting,
                    onPressed: (isSubmitting || _selectedMethodId == null) ? null : () {
                      final amount = double.tryParse(_amountController.text.trim());
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount')));
                        return;
                      }
                       final pin = _pinController.text.trim();
                       if (pin.length < 4) {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your wallet PIN')));
                         return;
                       }
                       context.read<WalletCubit>().requestWithdrawal(
                         amount: amount,
                         currency: _selectedCurrency,
                         payoutMethodId: _selectedMethodId!,
                         pin: pin,
                       );
                    },
                  ),
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
      width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
    ),
  );
}

class _KycGateBanner extends StatelessWidget {
  final VoidCallback onVerify;
  const _KycGateBanner({required this.onVerify});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: Colors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Identity verification required', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                const Text('To withdraw funds you must verify your identity. This is a quick one-time process.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 8),
                GestureDetector(onTap: onVerify, child: const Text('Verify identity →', style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMethodCard extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyMethodCard({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAdd,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline, color: AppColors.primary.withValues(alpha: 0.7), size: 20),
            const SizedBox(width: 10),
            Text('Add M-Pesa number', style: TextStyle(color: AppColors.primary.withValues(alpha: 0.8), fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _AddMpesaForm extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onAdd;
  final VoidCallback onCancel;

  const _AddMpesaForm({
    required this.controller,
    required this.isLoading,
    required this.onAdd,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: '07XXXXXXXX',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            prefixText: '+254  ',
            prefixStyle: const TextStyle(color: Colors.white60),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: TextButton(onPressed: onCancel, child: const Text('Cancel', style: TextStyle(color: Colors.white38)))),
            const SizedBox(width: 12),
            Expanded(child: PrimaryButton(text: 'Save', isLoading: isLoading, onPressed: onAdd)),
          ],
        ),
      ],
    );
  }
}
