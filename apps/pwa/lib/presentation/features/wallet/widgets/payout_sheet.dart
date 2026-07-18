import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_cubit.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_state.dart';
import 'package:lynk_x/presentation/features/wallet/models/wallet_model.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

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
    _amountController.addListener(() => setState(() {}));
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
    return b?.cashBalance;
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
          AppSnackBars.showSuccess(ctx, 'Withdrawal submitted. Funds will be sent once processed.');
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
                                ? context.accentColor.withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected ? context.accentColor.withValues(alpha: 0.5) : Colors.white12,
                            ),
                          ),
                          child: Text(
                            c,
                            style: TextStyle(
                              color: selected ? context.accentColor : Colors.white54,
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
                    prefixStyle: TextStyle(color: context.accentColor, fontWeight: FontWeight.w600),
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
                          color: isSelected ? context.accentColor.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? context.accentColor.withValues(alpha: 0.4) : Colors.white12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.account_balance_wallet, color: isSelected ? context.accentColor : Colors.white38, size: 20),
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
                            if (isSelected) Icon(Icons.check_circle, color: context.accentColor, size: 20),
                          ],
                        ),
                      ),
                    );
                  }),
                  if (!_showAddMethod)
                    TextButton.icon(
                      onPressed: () => setState(() => _showAddMethod = true),
                      icon: Icon(Icons.add, size: 16, color: context.accentColor),
                      label: Text('Add another method', style: TextStyle(color: context.accentColor, fontSize: 13)),
                    ),
                ],

                if (_showAddMethod)
                  _AddMethodForm(
                    controller: _phoneController,
                    isLoading: isAddingMethod,
                    onAdd: (provider, identity, label) {
                      context.read<WalletCubit>().addPayoutMethod(
                        providerName: provider,
                        identity:     identity,
                        label:        label,
                      );
                      setState(() => _showAddMethod = false);
                    },
                    onCancel: () => setState(() => _showAddMethod = false),
                  ),

                if (_selectedMethodId != null && _amountController.text.isNotEmpty && (double.tryParse(_amountController.text) ?? 0) > 0)
                  Builder(builder: (context) {
                    final m = state.payoutMethods.firstWhere((e) => e['id'] == _selectedMethodId, orElse: () => {});
                    final p = m['platform_payment_providers'] as Map<String, dynamic>?;
                    final base = (p?['base_fee_usd'] as num?)?.toDouble() ?? 0.0;
                    final pct = (p?['fee_percent'] as num?)?.toDouble() ?? 0.0;
                    final amt = double.tryParse(_amountController.text) ?? 0.0;
                    final fee = base + (amt * (pct / 100));
                    final total = amt + fee;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 24, top: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            const Text('Withdrawal Amount', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            Text('$_selectedCurrency ${amt.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                          ]),
                          const SizedBox(height: 8),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            const Text('Est. Processing Fee', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            Text('$_selectedCurrency ${fee.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                          ]),
                          const Divider(color: Colors.white10, height: 24),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            const Text('Total Deducted', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                            Text('$_selectedCurrency ${total.toStringAsFixed(2)}', style: TextStyle(color: context.accentColor, fontSize: 14, fontWeight: FontWeight.bold)),
                          ]),
                        ],
                      ),
                    );
                  }),

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
                        AppSnackBars.showInfo(context, 'Please enter a valid amount');
                        return;
                      }
                       final pin = _pinController.text.trim();
                       if (pin.length < 4) {
                         AppSnackBars.showInfo(context, 'Please enter your wallet PIN');
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
          border: Border.all(color: context.accentColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline, color: context.accentColor.withValues(alpha: 0.7), size: 20),
            const SizedBox(width: 10),
            Text('Add payout destination', style: TextStyle(color: context.accentColor.withValues(alpha: 0.8), fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _AddMethodForm extends StatefulWidget {
  final TextEditingController controller;
  final bool isLoading;
  final void Function(String provider, String identity, String label) onAdd;
  final VoidCallback onCancel;

  const _AddMethodForm({
    required this.controller,
    required this.isLoading,
    required this.onAdd,
    required this.onCancel,
  });

  @override
  State<_AddMethodForm> createState() => _AddMethodFormState();
}

class _AddMethodFormState extends State<_AddMethodForm> {
  String? _selectedProvider;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WalletCubit>().state;
    final providers = state.paymentProviders;

    // Determine currently active provider value
    final currentProvider = providers.any((p) => p['provider_name'] == _selectedProvider)
        ? _selectedProvider!
        : (providers.isNotEmpty ? providers.first['provider_name'] as String : 'mpesa_daraja');

    // Extract selected provider details
    final selectedProviderConfig = providers.firstWhere(
      (p) => p['provider_name'] == currentProvider,
      orElse: () => {
        'provider_name': 'mpesa_daraja',
        'display_name': 'M-Pesa Mobile Money',
        'ui_config': <String, dynamic>{},
      },
    );

    final metadata = selectedProviderConfig['ui_config'] as Map<String, dynamic>? ?? {};
    final validationRegex = metadata['validation_regex'] as String?;
    final inputType = metadata['input_type'] as String?;
    final prefix = metadata['prefix'] as String?;
    final hint = metadata['hint'] as String?;

    final isPhone = inputType == 'phone' || currentProvider.contains('mpesa');
    final keyboardType = isPhone ? TextInputType.phone : TextInputType.text;
    final hintText = hint ?? (isPhone ? '07XXXXXXXX' : 'Enter account number or email');
    final prefixText = prefix ?? (isPhone ? '+254  ' : '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentProvider,
              isExpanded: true,
              dropdownColor: AppColors.tertiary,
              style: const TextStyle(color: Colors.white),
              items: providers.isNotEmpty
                  ? providers.map((p) {
                      return DropdownMenuItem<String>(
                        value: p['provider_name'] as String,
                        child: Text(p['display_name'] as String? ?? p['provider_name'] as String),
                      );
                    }).toList()
                  : const [
                      DropdownMenuItem(value: 'mpesa_daraja', child: Text('M-Pesa Mobile Money')),
                    ],
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedProvider = v;
                    widget.controller.clear();
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            prefixText: prefixText,
            prefixStyle: const TextStyle(color: Colors.white60),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: TextButton(onPressed: widget.onCancel, child: const Text('Cancel', style: TextStyle(color: Colors.white38)))),
            const SizedBox(width: 12),
            Expanded(child: PrimaryButton(
              text: 'Save', 
              isLoading: widget.isLoading, 
              onPressed: () {
                final raw = widget.controller.text.trim();
                if (raw.isEmpty) return;

                // Validate using regex if present
                if (validationRegex != null && validationRegex.isNotEmpty) {
                  final regExp = RegExp(validationRegex);
                  if (!regExp.hasMatch(raw)) {
                    AppSnackBars.showError(context, 'Invalid format. Must match pattern: $hintText');
                    return;
                  }
                }

                // If isPhone, enforce simple validation length check
                if (isPhone && raw.length < 9) {
                  AppSnackBars.showError(context, 'Invalid phone number length.');
                  return;
                }

                final identity = isPhone
                    ? (raw.startsWith('+') ? raw : '+254${raw.replaceFirst(RegExp(r'^0'), '')}')
                    : raw;

                final display = selectedProviderConfig['display_name'] as String? ?? 'Payout Method';
                final label = isPhone ? '$display $identity' : '$display Account';

                widget.onAdd(currentProvider, identity, label);
              }
            )),
          ],
        ),
      ],
    );
  }
}
