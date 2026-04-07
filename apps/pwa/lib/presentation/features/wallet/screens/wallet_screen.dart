import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/core/utils/breakpoints.dart';

import 'package:lynk_x/presentation/features/wallet/cubit/wallet_cubit.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_state.dart';
import 'package:lynk_x/presentation/features/wallet/models/wallet_model.dart';

/// WalletPage — displays the user's balances and transaction history.
///
/// Consumed via the /wallet route. Calls [WalletCubit.init] on first mount
/// to load data; subsequent navigation hits are served from BLoC state
/// (global cubit — no re-fetch on every route push).
///
/// Features:
/// - Multi-currency balance cards
/// - Paginated transaction activity feed (infinite scroll)
/// - Top-up (opens payment gateway intent)
/// - Live balance updates via Supabase Realtime
class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Lazy-init: fetch data the first time the page mounts
    context.read<WalletCubit>().init();

    // Infinite scroll trigger
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        elevation: 0,
        title: Text(
          'Wallet',
          style: AppTypography.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_card, color: Colors.white),
            tooltip: 'Top up wallet',
            onPressed: _showTopUpDialog,
          ),
        ],
      ),
      body: BlocConsumer<WalletCubit, WalletState>(
        // Only rebuild balance cards when balances change
        buildWhen: (prev, curr) =>
            prev.isLoading != curr.isLoading ||
            prev.balances != curr.balances ||
            prev.transactions != curr.transactions ||
            prev.isLoadingMore != curr.isLoadingMore,
        // Listen for top-up redirect OR real-time balance increases
        listenWhen: (prev, curr) {
          // Detect balance increases (top-ups, refunds, etc.)
          if (prev.balances.isNotEmpty && curr.balances.isNotEmpty) {
            for (final currBal in curr.balances) {
              final prevBal = prev.balances.cast<WalletBalance?>().firstWhere(
                (b) => b?.currency == currBal.currency,
                orElse: () => null,
              );
              if (prevBal != null && currBal.balance > prevBal.balance) {
                return true;
              }
            }
          }
          return prev.topUpPaymentUrl != curr.topUpPaymentUrl;
        },
        listener: (context, state) {
          // Case: Successful top-up redirect
          if (state.topUpPaymentUrl != null) {
            _openPaymentUrl(state.topUpPaymentUrl!);
          } else {
            // Case: Internal balance increase detected by listenWhen
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.account_balance_wallet, color: Colors.white),
                    SizedBox(width: 12),
                    Text('Balance Updated — New funds available!'),
                  ],
                ),
                backgroundColor: AppColors.primary,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 4),
              ),
            );
          }
        },
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (state.error != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.read<WalletCubit>().refresh(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => context.read<WalletCubit>().refresh(),
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── Balance Cards ──────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _BalanceSection(balances: state.balances),
                ),

                // ── Section Header ─────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Text(
                      'Recent Activity',
                      style: AppTypography.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),

                // ── Transaction List ───────────────────────────────────────
                if (state.transactions.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'No transactions yet.',
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == state.transactions.length) {
                          return state.isLoadingMore
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink();
                        }
                        return _TransactionTile(tx: state.transactions[index]);
                      },
                      childCount: state.transactions.length + 1,
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Top-up Dialog ──────────────────────────────────────────────────────────

  void _showTopUpDialog() {
    final amountController = TextEditingController();
    String selectedCurrency = 'KES';
    final cubit = context.read<WalletCubit>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.fromLTRB(
            16, 24, 16,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: AppColors.tertiary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Top Up Wallet',
                style: AppTypography.inter(
                  fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  labelStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixText: selectedCurrency,
                  suffixStyle: TextStyle(color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedCurrency,
                dropdownColor: AppColors.tertiary,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: const ['KES', 'NGN', 'USD', 'GBP'].map((c) =>
                  DropdownMenuItem(value: c, child: Text(c))
                ).toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => selectedCurrency = val);
                },
              ),
              const SizedBox(height: 24),
              BlocBuilder<WalletCubit, WalletState>(
                builder: (context, state) => SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: state.topUpStatus == TopUpStatus.submitting
                        ? null
                        : () {
                            final amount = double.tryParse(amountController.text.trim());
                            if (amount == null || amount <= 0) return;
                            Navigator.pop(ctx);
                            cubit.initiateTopUp(
                              amount: amount,
                              currency: selectedCurrency,
                            );
                          },
                    child: state.topUpStatus == TopUpStatus.submitting
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black,
                            ),
                          )
                        : const Text(
                            'Continue to Payment',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPaymentUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open payment page')),
        );
      }
    }
    
    // Reset top-up status so the user can try again or see their updated balance
    if (mounted) context.read<WalletCubit>().resetTopUp();
  }
}

// ── Sub-Widgets ────────────────────────────────────────────────────────────────

class _BalanceSection extends StatelessWidget {
  final List<WalletBalance> balances;
  const _BalanceSection({required this.balances});

  @override
  Widget build(BuildContext context) {
    if (balances.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No wallets found.', style: TextStyle(color: Colors.white38)),
      );
    }

    // Card height scales slightly on larger screens
    final cardHeight = Breakpoints.isTablet(context) ? 140.0 : 120.0;

    return SizedBox(
      height: cardHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        itemCount: balances.length,
        itemBuilder: (_, i) => _BalanceCard(balance: balances[i]),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final WalletBalance balance;
  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    // Width adapts to screen: 45% of screen width on phones, capped at 220px on tablets
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.45).clamp(160.0, 220.0);

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.2),
            Colors.white.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            balance.currency,
            style: AppTypography.inter(
              fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${balance.currency} ${balance.balance.toStringAsFixed(2)}',
            style: AppTypography.inter(
              fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold,
            ),
          ),
          if (balance.pendingBalance > 0)
            Text(
              '+ ${balance.currency} ${balance.pendingBalance.toStringAsFixed(2)} pending',
              style: AppTypography.inter(fontSize: 10, color: Colors.white38),
            ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final WalletTransaction tx;
  const _TransactionTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isIncoming = tx.category == 'incoming';
    final color = isIncoming ? AppColors.primary : Colors.red.shade400;
    final sign  = isIncoming ? '+' : '-';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
                color: color, size: 18,
              ),
            ),
            const SizedBox(width: 12),
            // Label
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.reason.replaceAll('_', ' ').toUpperCase(),
                    style: AppTypography.inter(
                      fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${tx.createdAt.day.toString().padLeft(2,'0')}/'
                    '${tx.createdAt.month.toString().padLeft(2,'0')}/'
                    '${tx.createdAt.year}',
                    style: AppTypography.inter(fontSize: 10, color: Colors.white38),
                  ),
                ],
              ),
            ),
            // Amount
            Text(
              '$sign ${tx.currency} ${tx.amount.toStringAsFixed(2)}',
              style: AppTypography.inter(
                fontSize: 14, fontWeight: FontWeight.bold, color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
