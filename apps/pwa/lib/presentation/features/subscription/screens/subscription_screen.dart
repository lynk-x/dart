import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_core/core.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _supabase = Supabase.instance.client;

  // ── loading / processing ───────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _hasError = false;

  // ── plan data ──────────────────────────────────────────────────────────────
  _PlanData? _monthlyPlan;
  _PlanData? _yearlyPlan;
  String _interval = 'month'; // 'month' | 'year'

  // ── current subscription ───────────────────────────────────────────────────
  String? _activeSubId;
  String? _activePlanId;
  DateTime? _activeEndsAt;

  // ── context for payment ────────────────────────────────────────────────────
  String _walletCurrency = 'KES';
  double _walletBalance = 0;

  // ── M-Pesa async wait ─────────────────────────────────────────────────────
  bool _waitingMpesa = false;
  RealtimeChannel? _subChannel;
  Timer? _mpesaCountdownTimer;
  int _mpesaSecondsLeft = 180;

  // ── derived ───────────────────────────────────────────────────────────────
  _PlanData? get _selected => _interval == 'year' ? _yearlyPlan : _monthlyPlan;

  bool get _isActivePlan => _selected?.id == _activePlanId;

  bool get _walletSufficient =>
      _walletBalance >= (_selected?.price ?? double.infinity);

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subChannel?.unsubscribe();
    _mpesaCountdownTimer?.cancel();
    super.dispose();
  }

  void _startMpesaCountdown() {
    _mpesaCountdownTimer?.cancel();
    _mpesaSecondsLeft = 180;
    _mpesaCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_mpesaSecondsLeft > 0) _mpesaSecondsLeft--;
      });
    });
  }

  void _cancelMpesaCountdown() {
    _mpesaCountdownTimer?.cancel();
    _mpesaCountdownTimer = null;
  }

  // ── data loading ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final uid = _supabase.auth.currentUser?.id;

      final results = await Future.wait<dynamic>([
        // Plans + prices + features
        _supabase
            .from('subscription_plans')
            .select(
                'id, interval, display_name, '
                'subscription_prices(id, country_code, currency, amount), '
                'plan_features(subscription_features(display_name))')
            .eq('is_active', true)
            .eq('product_type', 'attendee_premium'),

        // User country (null-safe ternary — avoids type inference failure on if/else)
        uid != null
            ? _supabase
                .from('user_profile')
                .select('country_code')
                .eq('id', uid)
                .maybeSingle()
            : Future<dynamic>.value(null),

        // Active subscription
        _supabase
            .from('subscriptions')
            .select('id, plan_id, ends_at')
            .inFilter('status', ['active', 'trialing'])
            .eq('is_latest', true)
            .maybeSingle(),

        // Wallet balance (prefer KES, fall back to USD)
        _supabase
            .from('account_wallets')
            .select('currency, balance')
            .order('currency'),
      ]);

      final plansRaw = results[0] as List;
      final profileRaw = results[1] as Map<String, dynamic>?;
      final subRaw = results[2] as Map<String, dynamic>?;
      final walletsRaw = results[3] as List;

      final country = (profileRaw?['country_code'] as String?) ?? '';

      // Resolve wallet balance — prefer local currency
      String walletCurrency = 'USD';
      double walletBalance = 0;
      for (final w in walletsRaw) {
        final c = w['currency'] as String;
        final b = (w['balance'] as num).toDouble();
        if (c == 'KES' && country == 'KE') {
          walletCurrency = 'KES';
          walletBalance = b;
          break;
        }
        if (c == 'USD') {
          walletCurrency = 'USD';
          walletBalance = b;
        }
      }

      _PlanData? monthly;
      _PlanData? yearly;

      for (final p in plansRaw) {
        final plan = _PlanData.fromSupabase(p as Map<String, dynamic>, country);
        if (plan.interval == 'month') monthly = plan;
        if (plan.interval == 'year') yearly = plan;
      }

      if (!mounted) return;
      setState(() {
        _walletCurrency = walletCurrency;
        _walletBalance = walletBalance;
        _monthlyPlan = monthly;
        _yearlyPlan = yearly;
        _activeSubId = subRaw?['id'] as String?;
        _activePlanId = subRaw?['plan_id'] as String?;
        _activeEndsAt = subRaw?['ends_at'] != null
            ? DateTime.parse(subRaw!['ends_at'] as String)
            : null;
        // Pre-select the currently active interval
        if (_activePlanId == yearly?.id) _interval = 'year';
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; _hasError = true; });
    }
  }

  // ── payment flows ─────────────────────────────────────────────────────────

  Future<void> _payWithWallet() async {
    final plan = _selected;
    if (plan == null) return;

    Navigator.pop(context); // close payment sheet
    setState(() => _isProcessing = true);

    try {
      await _supabase.rpc('purchase_subscription', params: {
        'p_price_id': plan.priceId,
        'p_provider': 'wallet',
      });

      if (!mounted) return;
      _showSuccess();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _payWithMpesa(String phone) async {
    final plan = _selected;
    if (plan == null) return;

    Navigator.pop(context); // close payment sheet
    setState(() {
      _isProcessing = true;
      _waitingMpesa = true;
    });
    _startMpesaCountdown();

    // Listen for the webhook-created subscription row
    _subChannel = _supabase
        .channel('sub_watch_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'subscriptions',
          callback: (_) {
            if (!_waitingMpesa || !mounted) return;
            _cancelMpesaCountdown();
            setState(() {
              _waitingMpesa = false;
              _isProcessing = false;
            });
            _subChannel?.unsubscribe();
            _showSuccess();
          },
        )
        .subscribe();

    try {
      await _supabase.functions.invoke(
        'initiate-subscription-payment',
        body: {
          'price_id': plan.priceId,
          'phone': phone,
          'provider': 'mpesa_daraja',
        },
      );
      // UI now shows "waiting for M-Pesa" — handled via the realtime listener above.
      // Timeout after 3 minutes.
      Future.delayed(const Duration(minutes: 3), () {
        if (!mounted || !_waitingMpesa) return;
        _cancelMpesaCountdown();
        setState(() {
          _waitingMpesa = false;
          _isProcessing = false;
        });
        _subChannel?.unsubscribe();
        _showError('M-Pesa payment timed out. Please try again.');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _waitingMpesa = false;
      });
      _subChannel?.unsubscribe();
      _showError(e.toString());
    }
  }

  Future<void> _cancelSubscription() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Subscription?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          _activeEndsAt != null
              ? 'Your Premium access continues until ${_fmt(_activeEndsAt!)}. You won\'t be charged again.'
              : 'Your access will end at the end of the current billing period.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Premium',
                style: TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true || _activeSubId == null) return;

    setState(() => _isProcessing = true);
    try {
      await _supabase.rpc('cancel_subscription', params: {
        'p_subscription_id': _activeSubId,
        'p_reason': 'user_requested',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Subscription cancelled. Access continues until period end.'),
      ));
      _load();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── payment sheet ─────────────────────────────────────────────────────────

  void _showPaymentSheet() {
    final plan = _selected;
    if (plan == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _PaymentSheet(
        plan: plan,
        walletBalance: _walletBalance,
        walletCurrency: _walletCurrency,
        walletSufficient: _walletSufficient,
        onWallet: _payWithWallet,
        onTopUp: () {
          Navigator.pop(ctx);
          context.push('/wallet');
        },
        onMpesa: _payWithMpesa,
      ),
    );
  }

  // ── feedback helpers ──────────────────────────────────────────────────────

  void _showSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Welcome to Premium!'),
      backgroundColor: AppColors.primary,
    ));
    _load();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
    ));
  }

  String _fmt(DateTime dt) =>
      '${dt.day} ${_months[dt.month - 1]} ${dt.year}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 28, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Image.asset(
          'assets/images/lynk-x_combined-logo.png',
          width: 180,
          fit: BoxFit.contain,
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _hasError
              ? _buildError()
              : _monthlyPlan == null
                  ? _buildNoPlan()
                  : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'Could not load plans',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check your connection and try again.',
              style: TextStyle(color: Colors.white38, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _hasError = false);
                _load();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoPlan() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.workspace_premium,
              size: 64, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No plans available',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final plan = _selected!;

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
          child: Column(
            children: [
              // ── Hero icon ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.star_rounded,
                    size: 56, color: AppColors.secondary),
              ),
              const SizedBox(height: 20),

              const Text(
                'Lynk-X Premium',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'Enhance your event experience. Ad-free forums, exclusive badge, and early access to every new feature.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 15,
                    height: 1.5),
              ),

              const SizedBox(height: 28),

              // ── Interval toggle ────────────────────────────────────────
              if (_yearlyPlan != null) _buildIntervalToggle(),

              const SizedBox(height: 28),

              // ── Features ───────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  children: plan.features.asMap().entries.map((e) {
                    return Padding(
                      padding: EdgeInsets.only(
                          bottom: e.key < plan.features.length - 1 ? 14 : 0),
                      child: _FeatureRow(text: e.value),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 28),

              // ── Price ──────────────────────────────────────────────────
              _buildPriceDisplay(plan),

              if (_isActivePlan && _activeEndsAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Renews ${_fmt(_activeEndsAt!)}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 13),
                ),
              ],

              const SizedBox(height: 12),
              Text(
                'Cancel anytime before renewal. No refunds on current period.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 12,
                    height: 1.4),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),

        // ── Sticky bottom CTA ─────────────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomCTA(plan),
        ),

        // ── M-Pesa waiting overlay ────────────────────────────────────
        if (_waitingMpesa) _buildMpesaWaiting(),
      ],
    );
  }

  Widget _buildIntervalToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _ToggleOption(
            label: 'Monthly',
            selected: _interval == 'month',
            onTap: () => setState(() => _interval = 'month'),
          ),
          _ToggleOption(
            label: 'Yearly',
            badge: '2 months free',
            selected: _interval == 'year',
            onTap: () => setState(() => _interval = 'year'),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceDisplay(_PlanData plan) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '${plan.currency} ${plan.price.toStringAsFixed(0)}',
          style: const TextStyle(
              color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold),
        ),
        Text(
          plan.interval == 'year' ? ' / year' : ' / month',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4), fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildBottomCTA(_PlanData plan) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: BoxDecoration(
        color: AppColors.primaryBackground,
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isProcessing
                  ? null
                  : _isActivePlan
                      ? null
                      : _showPaymentSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor:
                    AppColors.primary.withValues(alpha: 0.3),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : Text(
                      _isActivePlan ? 'Current Plan' : 'Upgrade Now',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          if (_isActivePlan && _activeSubId != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isProcessing ? null : _cancelSubscription,
              child: Text(
                'Cancel Subscription',
                style: TextStyle(
                    color: Colors.redAccent.withValues(alpha: 0.7),
                    fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMpesaWaiting() {
    return Container(
      color: AppColors.primaryBackground.withValues(alpha: 0.92),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 24),
            const Text(
              'Waiting for M-Pesa...',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Check your phone and enter your M-Pesa PIN.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Expires in ${(_mpesaSecondsLeft ~/ 60).toString().padLeft(2, '0')}:${(_mpesaSecondsLeft % 60).toString().padLeft(2, '0')}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
            ),
            const SizedBox(height: 28),
            TextButton(
              onPressed: () {
                _cancelMpesaCountdown();
                _subChannel?.unsubscribe();
                setState(() {
                  _waitingMpesa = false;
                  _isProcessing = false;
                });
              },
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Payment Sheet ─────────────────────────────────────────────────────────────

class _PaymentSheet extends StatefulWidget {
  final _PlanData plan;
  final double walletBalance;
  final String walletCurrency;
  final bool walletSufficient;
  final VoidCallback onWallet;
  final VoidCallback onTopUp;
  final Future<void> Function(String phone) onMpesa;

  const _PaymentSheet({
    required this.plan,
    required this.walletBalance,
    required this.walletCurrency,
    required this.walletSufficient,
    required this.onWallet,
    required this.onTopUp,
    required this.onMpesa,
  });

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _phoneController = TextEditingController();
  bool _mpesaExpanded = false;
  String? _phoneError;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),

          const Text('Choose Payment Method',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            '${widget.plan.currency} ${widget.plan.price.toStringAsFixed(0)} · ${widget.plan.name}',
            style:
                TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
          ),
          const SizedBox(height: 24),

          // ── Wallet option ─────────────────────────────────────────────
          _PaymentOption(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Pay from Wallet',
            subtitle: widget.walletSufficient
                ? 'Balance: ${widget.walletCurrency} ${widget.walletBalance.toStringAsFixed(0)}'
                : 'Insufficient balance — top up first',
            enabled: widget.walletSufficient,
            onTap: widget.onWallet,
          ),

          if (!widget.walletSufficient)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onTopUp,
                icon: const Icon(Icons.add_card, size: 14),
                label: const Text('Top up wallet →'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ),

          const SizedBox(height: 12),

          // ── M-Pesa option ─────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PaymentOption(
                  icon: Icons.phone_android_outlined,
                  title: 'Pay with M-Pesa',
                  subtitle: 'STK push to your phone',
                  enabled: true,
                  trailing: Icon(
                    _mpesaExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white38,
                    size: 20,
                  ),
                  onTap: () =>
                      setState(() => _mpesaExpanded = !_mpesaExpanded),
                ),
                if (_mpesaExpanded) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) {
                      if (_phoneError != null) setState(() => _phoneError = null);
                    },
                    decoration: InputDecoration(
                      hintText: '7XXXXXXXX',
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3)),
                      prefixText: '+254 ',
                      prefixStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.redAccent),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      errorText: _phoneError,
                      errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      final phone = _phoneController.text.trim();
                      if (phone.length != 9) {
                        setState(() => _phoneError = 'Enter 9 digits after +254 (e.g. 712345678)');
                        return;
                      }
                      widget.onMpesa('+254$phone');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      minimumSize: const Size.fromHeight(50),
                      elevation: 0,
                    ),
                    child: const Text('Send STK Push',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ToggleOption extends StatelessWidget {
  final String label;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleOption({
    required this.label,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white60,
                  fontSize: 14,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(height: 2),
                Text(
                  badge!,
                  style: TextStyle(
                    color: selected
                        ? Colors.black.withValues(alpha: 0.6)
                        : AppColors.primary.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String text;
  const _FeatureRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
              color: AppColors.primary, shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 14, color: Colors.black),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final Widget? trailing;
  final VoidCallback onTap;

  const _PaymentOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white70, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12)),
                  ],
                ),
              ),
              trailing ??
                  Icon(Icons.chevron_right,
                      color: Colors.white.withValues(alpha: 0.3), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _PlanData {
  final String id;
  final String priceId;
  final String name;
  final String interval;
  final double price;
  final String currency;
  final List<String> features;

  const _PlanData({
    required this.id,
    required this.priceId,
    required this.name,
    required this.interval,
    required this.price,
    required this.currency,
    required this.features,
  });

  factory _PlanData.fromSupabase(Map<String, dynamic> p, String country) {
    final prices = (p['subscription_prices'] as List?) ?? [];

    // Pick country-specific price first, fall back to global (null country_code)
    Map<String, dynamic>? best;
    for (final pr in prices) {
      final cc = pr['country_code'] as String?;
      if (cc == country && country.isNotEmpty) {
        best = pr as Map<String, dynamic>;
        break;
      }
      if (cc == null) best ??= pr as Map<String, dynamic>;
    }

    final features = ((p['plan_features'] as List?) ?? [])
        .map((pf) {
          final sf = (pf as Map<String, dynamic>)['subscription_features']
              as Map<String, dynamic>?;
          return sf?['display_name'] as String? ?? '';
        })
        .where((f) => f.isNotEmpty)
        .toList();

    return _PlanData(
      id: p['id'] as String,
      priceId: best?['id'] as String? ?? '',
      name: p['display_name'] as String,
      interval: p['interval'] as String,
      price: (best?['amount'] as num?)?.toDouble() ?? 0,
      currency: best?['currency'] as String? ?? 'USD',
      features: features,
    );
  }
}
