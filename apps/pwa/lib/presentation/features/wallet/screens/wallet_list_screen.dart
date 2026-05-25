import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_cubit.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_state.dart';
import 'package:lynk_x/presentation/features/wallet/models/wallet_model.dart';

class WalletListPage extends StatelessWidget {
  const WalletListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'My Wallets',
          style: AppTypography.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _showAddWalletDialog(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: BlocBuilder<WalletCubit, WalletState>(
        builder: (context, state) {
          if (state.isLoading && state.balances.isEmpty) {
            return Center(child: CircularProgressIndicator(color: context.accentColor));
          }

          if (state.balances.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.white24),
                  const SizedBox(height: 16),
                  const Text('No wallets found', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => _showAddWalletDialog(context),
                    style: ElevatedButton.styleFrom(backgroundColor: context.accentColor),
                    child: const Text('Add your first wallet', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: state.balances.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final balance = state.balances[index];
              return _WalletCard(balance: balance);
            },
          );
        },
      ),
    );
  }

  void _showAddWalletDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add New Wallet', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Select a currency to create a new wallet.', style: TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: ['KES', 'USD', 'GBP', 'EUR', 'NGN', 'UGX'].map((c) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    context.read<WalletCubit>().createWallet(c);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(c, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  final WalletBalance balance;
  const _WalletCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/wallet/list/${balance.currency}'),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: context.accentColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.account_balance_wallet, color: context.accentColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    balance.currency,
                    style: AppTypography.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cash: ${balance.cashBalance.toStringAsFixed(2)}${balance.creditBalance > 0 ? ' • Credit: ${balance.creditBalance.toStringAsFixed(2)}' : ''}',
                    style: AppTypography.inter(fontSize: 13, color: Colors.white54),
                  ),
                  if (balance.pendingBalance > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.lock_clock, size: 12, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          'Pending / Held: ${balance.pendingBalance.toStringAsFixed(2)}',
                          style: AppTypography.inter(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
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
