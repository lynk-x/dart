import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_cubit.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_state.dart';
import 'package:lynk_x/presentation/features/wallet/screens/wallet_transactions_screen.dart';
import 'package:intl/intl.dart';
import 'package:lynk_x/l10n/app_localizations.dart';
import 'package:lynk_x/presentation/features/wallet/models/wallet_model.dart';

class WalletHistoryPage extends StatefulWidget {
  const WalletHistoryPage({super.key});

  @override
  State<WalletHistoryPage> createState() => _WalletHistoryPageState();
}

class _WalletHistoryPageState extends State<WalletHistoryPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletCubit>().setCurrency(null); // Load all transactions
    });

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        context.read<WalletCubit>().loadMoreTransactions();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Map<String, List<WalletTransaction>> _groupTransactions(
    List<WalletTransaction> transactions,
    AppLocalizations? l10n,
  ) {
    final groups = <String, List<WalletTransaction>>{};
    for (final tx in transactions) {
      final date = DateTime(tx.createdAt.year, tx.createdAt.month, tx.createdAt.day);
      String label;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));

      if (date == today) {
        label = l10n?.today ?? 'Today';
      } else if (date == yesterday) {
        label = l10n?.yesterday ?? 'Yesterday';
      } else if (date.year == now.year) {
        label = DateFormat.MMMMd().format(date);
      } else {
        label = DateFormat.yMMMMd().format(date);
      }

      groups.putIfAbsent(label, () => []).add(tx);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Transaction History',
          style: AppTypography.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: BlocBuilder<WalletCubit, WalletState>(
        builder: (context, state) {
          if (state.isLoading && state.transactions.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          if (state.transactions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.history_rounded, size: 64, color: Colors.white12),
                  const SizedBox(height: 16),
                  const Text('No transactions found', style: TextStyle(color: Colors.white38)),
                ],
              ),
            );
          }

          final grouped = _groupTransactions(state.transactions, l10n);
          final sortedKeys = grouped.keys.toList();

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => context.read<WalletCubit>().refresh(),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: sortedKeys.length + 1,
              itemBuilder: (context, groupIndex) {
                if (groupIndex == sortedKeys.length) {
                  return state.isLoadingMore
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
                        )
                      : const SizedBox(height: 80);
                }

                final label = sortedKeys[groupIndex];
                final txs = grouped[label]!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        label.toUpperCase(),
                        style: AppTypography.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white24,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    ...txs.map((tx) => TransactionTile(tx: tx)),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
