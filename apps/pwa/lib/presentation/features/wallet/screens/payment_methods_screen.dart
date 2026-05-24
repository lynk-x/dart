import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import '../cubit/wallet_cubit.dart';
import '../cubit/wallet_state.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<WalletCubit>().loadPayoutMethods();
  }

  void _confirmDelete(BuildContext context, String methodId, String identity) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Remove Method', style: AppTypography.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to remove $identity?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              context.read<WalletCubit>().deletePayoutMethod(methodId);
              Navigator.pop(ctx);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
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
          'Saved Payment Methods',
          style: AppTypography.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: BlocConsumer<WalletCubit, WalletState>(
        listenWhen: (prev, curr) => prev.withdrawError != curr.withdrawError && curr.withdrawError != null,
        listener: (context, state) {
          if (state.withdrawError != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.withdrawError!), backgroundColor: Colors.redAccent),
            );
          }
        },
        builder: (context, state) {
          if (state.payoutMethods.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.white24),
                  const SizedBox(height: 16),
                  Text('No saved methods', style: AppTypography.inter(fontSize: 18, color: Colors.white54, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Saved withdrawal destinations will appear here.', style: TextStyle(color: Colors.white38)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: state.payoutMethods.length,
            itemBuilder: (context, index) {
              final m = state.payoutMethods[index];
              final provider = m['platform_payment_providers'] as Map<String, dynamic>?;
              final identity = m['provider_identity'] as String;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.account_balance, color: context.accentColor, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(provider?['display_name'] ?? 'Method', style: AppTypography.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(identity, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.white38),
                      onPressed: () => _confirmDelete(context, m['id'], identity),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddMethodSheet(context),
        backgroundColor: context.accentColor,
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text('Add Method', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showAddMethodSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 24,
        ),
        child: const _AddMethodSheet(),
      ),
    );
  }
}

class _AddMethodSheet extends StatefulWidget {
  const _AddMethodSheet();

  @override
  State<_AddMethodSheet> createState() => _AddMethodSheetState();
}

class _AddMethodSheetState extends State<_AddMethodSheet> {
  final TextEditingController _controller = TextEditingController();
  String _provider = 'mpesa_daraja';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WalletCubit, WalletState>(
      listenWhen: (prev, curr) => prev.withdrawStatus != curr.withdrawStatus,
      listener: (context, state) {
        if (state.withdrawStatus == WithdrawStatus.idle && state.withdrawError == null) {
          Navigator.pop(context); // Close sheet on success
        }
      },
      builder: (context, state) {
        final isLoading = state.withdrawStatus == WithdrawStatus.addingMethod;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Payment Method', style: AppTypography.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _provider,
                  isExpanded: true,
                  dropdownColor: AppColors.tertiary,
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'mpesa_daraja', child: Text('M-Pesa Mobile Money')),
                    DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer (SWIFT/IBAN)')),
                    DropdownMenuItem(value: 'stripe', child: Text('Stripe Connect')),
                  ],
                  onChanged: (v) => setState(() => _provider = v!),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: _provider == 'mpesa_daraja' ? TextInputType.phone : TextInputType.text,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _provider == 'mpesa_daraja' ? '07XXXXXXXX' : 'Enter account number or email',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                prefixText: _provider == 'mpesa_daraja' ? '+254  ' : '',
                prefixStyle: const TextStyle(color: Colors.white60),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            if (state.withdrawError != null && state.withdrawStatus == WithdrawStatus.error) ...[
              const SizedBox(height: 12),
              Text(state.withdrawError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            PrimaryButton(
              text: 'Save Method',
              isLoading: isLoading,
              onPressed: () {
                final raw = _controller.text.trim();
                if (raw.isEmpty) return;
                final identity = _provider == 'mpesa_daraja' 
                  ? (raw.startsWith('+') ? raw : '+254${raw.replaceFirst(RegExp(r'^0'), '')}')
                  : raw;
                
                final label = _provider == 'mpesa_daraja' 
                  ? 'M-Pesa $identity' 
                  : (_provider == 'bank_transfer' ? 'Bank Account' : 'Gateway');
                  
                context.read<WalletCubit>().addPayoutMethod(
                  providerName: _provider,
                  identity:     identity,
                  label:        label,
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
