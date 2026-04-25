import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
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
            icon: const Icon(Icons.arrow_upward, color: Colors.white),
            tooltip: 'Withdraw funds',
            onPressed: _showWithdrawDialog,
          ),
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
        // Notify on any incoming balance increase (top-ups, refunds, resale).
        listenWhen: (prev, curr) {
          if (prev.balances.isEmpty || curr.balances.isEmpty) return false;
          for (final currBal in curr.balances) {
            final prevBal = prev.balances.cast<WalletBalance?>().firstWhere(
              (b) => b?.currency == currBal.currency,
              orElse: () => null,
            );
            if (prevBal != null && currBal.balance > prevBal.balance) return true;
          }
          // Card top-up: redirect URL emitted
          return prev.topUpPaymentUrl != curr.topUpPaymentUrl &&
              curr.topUpPaymentUrl != null;
        },
        listener: (context, state) {
          if (state.topUpPaymentUrl != null) {
            _openCardPaymentUrl(state.topUpPaymentUrl!);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.account_balance_wallet, color: Colors.white),
                    SizedBox(width: 12),
                    Text('Funds received — balance updated!'),
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

  // ── Payout Sheet ───────────────────────────────────────────────────────────

  void _showWithdrawDialog() {
    final cubit = context.read<WalletCubit>();
    cubit.loadPayoutMethods();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BlocProvider.value(
        value: cubit,
        child: _PayoutSheet(currentBalances: cubit.state.balances),
      ),
    ).whenComplete(cubit.resetWithdraw);
  }

  // ── Top-up Sheet ───────────────────────────────────────────────────────────

  void _showTopUpDialog() {
    final cubit = context.read<WalletCubit>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BlocProvider.value(
        value: cubit,
        child: _TopUpSheet(currentBalances: cubit.state.balances),
      ),
    ).whenComplete(cubit.resetTopUp);
  }

  Future<void> _openCardPaymentUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Invalid payment URL. Please contact support.')),
        );
      }
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open payment page.')),
        );
      }
    }
    if (mounted) context.read<WalletCubit>().resetTopUp();
  }
}

// ── Sub-Widgets ────────────────────────────────────────────────────────────────

// ── Top-Up Sheet ──────────────────────────────────────────────────────────────

class _TopUpSheet extends StatefulWidget {
  final List<WalletBalance> currentBalances;
  const _TopUpSheet({required this.currentBalances});

  @override
  State<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<_TopUpSheet> {
  static const _mpesaCurrencies = {'KES', 'UGX', 'TZS', 'NGN'};
  static const _quickAmounts = {
    'KES': [500.0, 1000.0, 2500.0, 5000.0],
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
    if (amount == null || amount <= 0) return;
    final cubit = context.read<WalletCubit>();
    if (_isMpesa) {
      final phone = _phoneController.text.trim();
      if (phone.length < 9) return;
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
        Row(
          children: ['KES', 'USD', 'GBP'].map((c) {
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
                        ? AppColors.primary.withOpacity(0.15)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? AppColors.primary.withOpacity(0.5)
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
                          ? AppColors.primary.withOpacity(0.15)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary.withOpacity(0.5)
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
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            suffixText: _currency,
            suffixStyle: TextStyle(color: AppColors.primary),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
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
                  TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixText: '+254  ',
              prefixStyle: const TextStyle(color: Colors.white60),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
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

// ── Payout Sheet ──────────────────────────────────────────────────────────────

class _PayoutSheet extends StatefulWidget {
  final List<WalletBalance> currentBalances;
  const _PayoutSheet({required this.currentBalances});

  @override
  State<_PayoutSheet> createState() => _PayoutSheetState();
}

class _PayoutSheetState extends State<_PayoutSheet> {
  final _amountController = TextEditingController();
  final _phoneController  = TextEditingController();

  String  _selectedCurrency = 'KES';
  String? _selectedMethodId;
  bool    _showAddMethod    = false;

  @override
  void dispose() {
    _amountController.dispose();
    _phoneController.dispose();
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
              content: Text(
                'Withdrawal submitted. Funds will be sent once processed.',
              ),
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
                // Handle bar
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                Text(
                  'Withdraw Funds',
                  style: AppTypography.inter(
                    fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Funds move to escrow and are released to your payout method.',
                  style: AppTypography.inter(fontSize: 13, color: Colors.white38),
                ),
                const SizedBox(height: 20),

                // KYC gate banner
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primary.withOpacity(0.15)
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected
                                  ? AppColors.primary.withOpacity(0.5)
                                  : Colors.white12,
                            ),
                          ),
                          child: Text(
                            c,
                            style: TextStyle(
                              color: selected
                                  ? AppColors.primary
                                  : Colors.white54,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),

                // Available balance hint
                if (_selectedBalance != null)
                  Text(
                    'Available: $_selectedCurrency ${_selectedBalance!.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                const SizedBox(height: 10),

                // Amount input
                TextField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: const TextStyle(color: Colors.white24),
                    prefixText: '$_selectedCurrency  ',
                    prefixStyle: TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.w600),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Min: ~\$10 USD equivalent',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 20),

                // Payout method section
                Text(
                  'Payout Method',
                  style: AppTypography.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 8),

                if (state.payoutMethods.isEmpty && !_showAddMethod)
                  _EmptyMethodCard(
                    onAdd: () => setState(() => _showAddMethod = true),
                  )
                else ...[
                  for (final m in state.payoutMethods)
                    _MethodTile(
                      method: m,
                      isSelected: _selectedMethodId == m['id'],
                      onTap: () => setState(() {
                        _selectedMethodId = m['id'] as String;
                        _showAddMethod = false;
                      }),
                    ),
                  if (!_showAddMethod)
                    TextButton.icon(
                      onPressed: () => setState(() => _showAddMethod = true),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add M-Pesa number'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                      ),
                    ),
                ],

                // Inline add M-Pesa form
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _showAddMethod
                      ? _AddMpesaForm(
                          controller: _phoneController,
                          isLoading: isAddingMethod,
                          onAdd: () {
                            final raw = _phoneController.text.trim();
                            if (raw.isEmpty) return;
                            final phone = raw.startsWith('+')
                                ? raw
                                : '+254${raw.replaceFirst(RegExp(r'^0'), '')}';
                            context.read<WalletCubit>().addPayoutMethod(
                              providerName: 'mpesa_daraja',
                              identity:     phone,
                              label:        'M-Pesa $phone',
                            );
                            setState(() => _showAddMethod = false);
                          },
                          onCancel: () =>
                              setState(() => _showAddMethod = false),
                        )
                      : const SizedBox.shrink(),
                ),

                // Error
                if (state.withdrawStatus == WithdrawStatus.error &&
                    state.withdrawError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Text(
                      state.withdrawError!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (isSubmitting || _selectedMethodId == null)
                        ? null
                        : () {
                            final amount = double.tryParse(
                                _amountController.text.trim());
                            if (amount == null || amount <= 0) return;
                            context.read<WalletCubit>().requestWithdrawal(
                              amount:         amount,
                              currency:       _selectedCurrency,
                              payoutMethodId: _selectedMethodId!,
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor:
                          AppColors.primary.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          )
                        : const Text(
                            'Request Withdrawal',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Payout sub-widgets ─────────────────────────────────────────────────────────

class _KycGateBanner extends StatelessWidget {
  final VoidCallback onVerify;
  const _KycGateBanner({required this.onVerify});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.35)),
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
                const Text(
                  'Identity verification required',
                  style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Withdrawals require Tier 2 verification (Government ID).',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onVerify,
                  child: const Text(
                    'Verify identity →',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
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
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline,
                color: AppColors.primary.withOpacity(0.7), size: 20),
            const SizedBox(width: 10),
            Text(
              'Add M-Pesa number',
              style: TextStyle(
                color: AppColors.primary.withOpacity(0.8),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final Map<String, dynamic> method;
  final bool isSelected;
  final VoidCallback onTap;

  const _MethodTile({
    required this.method,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final provider = method['platform_payment_providers'] as Map<String, dynamic>? ?? {};
    final displayName = provider['display_name'] as String? ?? 'Payment Method';
    final identity    = method['provider_identity'] as String? ?? '';
    final metadata    = method['metadata'] as Map<String, dynamic>? ?? {};
    final label       = metadata['label'] as String? ?? '$displayName $identity';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withOpacity(0.5)
                : Colors.white12,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.phone_android_outlined,
              color: isSelected ? AppColors.primary : Colors.white38,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color:
                          isSelected ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    identity,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle,
                  color: AppColors.primary, size: 18),
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
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add M-Pesa number',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: '07XXXXXXXX',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixText: '+254  ',
              prefixStyle: const TextStyle(color: Colors.white60),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: isLoading ? null : onAdd,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('Save',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onCancel,
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white38)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
            AppColors.primary.withOpacity(0.2),
            Colors.white.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
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
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
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
                    '${tx.createdAt.toLocal().day.toString().padLeft(2,'0')}/'
                    '${tx.createdAt.toLocal().month.toString().padLeft(2,'0')}/'
                    '${tx.createdAt.toLocal().year}',
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
