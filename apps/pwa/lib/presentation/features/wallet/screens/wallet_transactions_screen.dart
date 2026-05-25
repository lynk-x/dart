import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_cubit.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_state.dart';
import 'package:lynk_x/presentation/features/wallet/models/wallet_model.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import 'package:lynk_x/presentation/features/wallet/widgets/top_up_sheet.dart';
import 'package:lynk_x/presentation/features/wallet/widgets/payout_sheet.dart';

class WalletTransactionsPage extends StatefulWidget {
  final String currency;
  const WalletTransactionsPage({super.key, required this.currency});

  @override
  State<WalletTransactionsPage> createState() => _WalletTransactionsPageState();
}

class _WalletTransactionsPageState extends State<WalletTransactionsPage> {
  final _scrollController = ScrollController();
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Top-ups', 'Withdrawals', 'Purchases', 'Transfers'];

  @override
  void initState() {
    super.initState();
    // Set the currency filter and refresh
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletCubit>().setCurrency(widget.currency);
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

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WalletCubit, WalletState>(
      listenWhen: (prev, curr) {
        // Balance increase notification
        if (prev.balances.isNotEmpty && curr.balances.isNotEmpty) {
          final pBal = prev.balances.cast<WalletBalance?>().firstWhere((b) => b?.currency == widget.currency, orElse: () => null);
          final cBal = curr.balances.cast<WalletBalance?>().firstWhere((b) => b?.currency == widget.currency, orElse: () => null);
          if (pBal != null && cBal != null && cBal.cashBalance > pBal.cashBalance) return true;
        }
        // Redirect URL emitted
        return prev.topUpPaymentUrl != curr.topUpPaymentUrl && curr.topUpPaymentUrl != null;
      },
      listener: (context, state) {
        if (state.topUpPaymentUrl != null) {
          _openCardPaymentUrl(context, state.topUpPaymentUrl!);
        } else {
          AppSnackBars.showSuccess(
            context,
            'Funds received — your ${widget.currency} balance has been updated.',
          );
        }
      },
      builder: (context, state) {
        final balance = state.balances.firstWhere(
          (b) => b.currency == widget.currency,
          orElse: () => WalletBalance(currency: widget.currency, cashBalance: 0, pendingBalance: 0, creditBalance: 0),
        );

        return Scaffold(
          backgroundColor: AppColors.primaryBackground,
          appBar: AppBar(
            backgroundColor: AppColors.primaryBackground,
            elevation: 0,
            centerTitle: true,
            title: Text(
              '${widget.currency} Wallet',
              style: AppTypography.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          body: RefreshIndicator(
            color: context.accentColor,
            onRefresh: () => context.read<WalletCubit>().refresh(),
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── Balance Header ──────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          context.accentColor.withValues(alpha: 0.15),
                          Colors.white.withValues(alpha: 0.02),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: context.accentColor.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Available Balance',
                          style: AppTypography.inter(fontSize: 14, color: Colors.white54),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          state.isPrivacyModeEnabled
                            ? '••••••'
                            : '${balance.currency} ${balance.cashBalance.toStringAsFixed(2)}',
                          style: AppTypography.inter(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (balance.creditBalance > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            state.isPrivacyModeEnabled
                              ? 'Credit: ••••••'
                              : 'Credit: ${balance.currency} ${balance.creditBalance.toStringAsFixed(2)}',
                            style: AppTypography.inter(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.greenAccent.shade400),
                          ),
                        ],
                        if (balance.pendingBalance > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            state.isPrivacyModeEnabled
                              ? '+ •••••• pending'
                              : '+ ${balance.currency} ${balance.pendingBalance.toStringAsFixed(2)} pending',
                            style: AppTypography.inter(fontSize: 12, color: context.accentColor.withValues(alpha: 0.7)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // ── Activity Header ─────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recent Activity',
                          style: AppTypography.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _filters.length,
                            separatorBuilder: (context, index) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final f = _filters[index];
                              final isSelected = f == _selectedFilter;
                              return GestureDetector(
                                onTap: () => setState(() => _selectedFilter = f),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected ? context.accentColor : Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: isSelected ? context.accentColor : Colors.white10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      f,
                                      style: TextStyle(
                                        color: isSelected ? Colors.black : Colors.white70,
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // ── Transaction List ───────────────────────────────────────
                Builder(
                  builder: (context) {
                    List<WalletTransaction> filteredTx = state.transactions;
                    if (_selectedFilter == 'Top-ups') {
                      filteredTx = filteredTx.where((t) => t.entryType == 'top_up' || t.reason.startsWith('top_up')).toList();
                    } else if (_selectedFilter == 'Withdrawals') {
                      filteredTx = filteredTx.where((t) => t.entryType == 'payout' || t.reason.startsWith('withdrawal')).toList();
                    } else if (_selectedFilter == 'Purchases') {
                      filteredTx = filteredTx.where((t) => t.reason.contains('purchase') || t.reason.contains('subscription')).toList();
                    } else if (_selectedFilter == 'Transfers') {
                      filteredTx = filteredTx.where((t) => t.reason.contains('transfer')).toList();
                    }

                    if (state.isLoading && state.transactions.isEmpty) {
                      return SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator(color: context.accentColor)),
                      );
                    }
                    if (filteredTx.isEmpty) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            'No $_selectedFilter transactions found.',
                            style: const TextStyle(color: Colors.white38),
                          ),
                        ),
                      );
                    }
                    
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index == filteredTx.length) {
                            return state.isLoadingMore
                                ? Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(child: CircularProgressIndicator(color: context.accentColor, strokeWidth: 2)),
                                  )
                                : const SizedBox(height: 100);
                          }
                          return TransactionTile(tx: filteredTx[index]);
                        },
                        childCount: filteredTx.length + 1,
                      ),
                    );
                  },
                ),

              ],
            ),
          ),
          bottomNavigationBar: WalletStickyFooter(
            onSend: () => _showWithdrawDialog(context),
            onReceive: () => _showTopUpDialog(context),
          ),
        );
      },
    );
  }

  Future<void> _openCardPaymentUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid payment URL. Please contact support.')),
        );
      }
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open payment page.')),
        );
      }
    }
    if (context.mounted) {
      context.read<WalletCubit>().resetTopUp();
    }
  }

  void _showWithdrawDialog(BuildContext context) {
    final cubit = context.read<WalletCubit>();
    cubit.loadPayoutMethods();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BlocProvider.value(
        value: cubit,
        child: PayoutSheet(
          currentBalances: cubit.state.balances,
          initialCurrency: widget.currency,
        ),
      ),
    ).whenComplete(cubit.resetWithdraw);
  }

  void _showTopUpDialog(BuildContext context) {
    final cubit = context.read<WalletCubit>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BlocProvider.value(
        value: cubit,
        child: TopUpSheet(
          currentBalances: cubit.state.balances,
          initialCurrency: widget.currency,
        ),
      ),
    ).whenComplete(cubit.resetTopUp);
  }
}

// I will need to move TransactionTile and WalletStickyFooter to shared widgets or keep them here
class TransactionTile extends StatelessWidget {
  final WalletTransaction tx;
  const TransactionTile({super.key, required this.tx});

  static const _reasonLabels = {
    'top_up_mpesa':      'M-Pesa Top Up',
    'top_up_card':       'Card Top Up',
    'ticket_purchase':   'Ticket Purchase',
    'ticket_refund':     'Ticket Refund',
    'subscription':      'Subscription Payment',
    'subscription_refund': 'Subscription Refund',
    'resale_sale':       'Ticket Resale — Sale',
    'resale_purchase':   'Ticket Resale — Purchase',
    'withdrawal':        'Withdrawal',
    'withdrawal_refund': 'Withdrawal Refund',
    'transfer_in':       'Transfer Received',
    'transfer_out':      'Transfer Sent',
  };

  String get _label =>
      _reasonLabels[tx.reason] ??
      tx.reason.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  @override
  Widget build(BuildContext context) {
    final isIncoming = tx.category == 'incoming';
    final color = isIncoming ? context.accentColor : Colors.red.shade400;
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _label,
                    style: AppTypography.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
                  ),
                  Text(
                    DateFormat.yMMMd().add_Hm().format(tx.createdAt),
                    style: AppTypography.inter(fontSize: 11, color: Colors.white30),
                  ),
                ],
              ),
            ),
            BlocBuilder<WalletCubit, WalletState>(
              builder: (context, state) {
                return Text(
                  state.isPrivacyModeEnabled 
                    ? '••••••'
                    : '$sign ${tx.currency} ${tx.amount.toStringAsFixed(2)}',
                  style: AppTypography.inter(fontSize: 15, fontWeight: FontWeight.bold, color: color),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class WalletStickyFooter extends StatelessWidget {
  final VoidCallback onSend;
  final VoidCallback onReceive;

  const WalletStickyFooter({
    super.key,
    required this.onSend,
    required this.onReceive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      decoration: BoxDecoration(
        color: AppColors.primaryBackground,
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: PrimaryButton(
              text: 'Send',
              onPressed: onSend,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              text: 'Receive',
              onPressed: onReceive,
            ),
          ),
        ],
      ),
    );
  }
}
