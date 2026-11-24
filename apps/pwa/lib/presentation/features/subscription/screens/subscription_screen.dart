import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/core/utils/safe_launch.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import 'subscription_widgets.dart';


class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> with WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;

  // ── loading / processing ───────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _hasError = false;

  // ── plan data ──────────────────────────────────────────────────────────────
  PlanData? _monthlyPlan;
  PlanData? _yearlyPlan;
  String _interval = 'month'; // 'month' | 'year'

  // ── current subscription ───────────────────────────────────────────────────
  String? _activeSubId;
  String? _activePlanId;
  DateTime? _activeEndsAt;

  // ── derived ───────────────────────────────────────────────────────────────
  PlanData? get _selected => _interval == 'year' ? _yearlyPlan : _monthlyPlan;

  bool get _isActivePlan => _selected?.id == _activePlanId;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  // ── data loading ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final uid = _supabase.auth.currentUser?.id;

        // Active subscription
      final activeSubQuery = _supabase
          .schema('api')
          .from('v1_subscriptions')
          .select('id, plan_id, ends_at')
          .inFilter('status', ['active', 'trialing'])
          .eq('is_latest', true);

      final results = await Future.wait<dynamic>([
        _supabase
            .schema('api')
            .rpc('get_subscription_catalog', params: {'p_product_type': 'attendee_premium'}),

        // Get user's owner attendee account country.
        uid != null
            ? _supabase
                .schema('api')
                .from('v1_account_memberships')
                .select('country_code')
                .eq('user_id', uid)
                .eq('type', 'attendee')
                .eq('role_slug', 'owner')
                .limit(1)
                .maybeSingle()
            : Future<dynamic>.value(null),

        // Active subscription (RLS automatically scopes to the authenticated user's account)
        uid != null ? activeSubQuery.maybeSingle() : Future<dynamic>.value(null),
      ]);

      final plansRaw = results[0] as List;
      final accountRaw = results[1] as Map<String, dynamic>?;
      final subRaw = results[2] as Map<String, dynamic>?;

      final country = (accountRaw?['country_code'] as String?) ?? '';

      PlanData? monthly;
      PlanData? yearly;

      for (final p in plansRaw) {
        final plan = PlanData.fromSupabase(p as Map<String, dynamic>, country);
        if (plan.interval == 'month') monthly = plan;
        if (plan.interval == 'year') yearly = plan;
      }

      if (!mounted) return;
      setState(() {
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
        _hasError = false;
      });
    } catch (e, stack) {
      debugPrint('[SubscriptionScreen] Error loading subscription plans: $e\n$stack');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  // ── payment flows ─────────────────────────────────────────────────────────

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
                style: TextStyle(color: AppColors.secondary)),
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
      await _supabase.schema('api').rpc('cancel_subscription', params: {
        'p_subscription_id': _activeSubId,
        'p_reason': 'user_requested',
      });
      if (!mounted) return;
      AppSnackBars.showInfo(context, 'Subscription cancelled. Access continues until period end.');
      _load();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toFriendlyMessage());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── checkout redirect ─────────────────────────────────────────────────────

  Future<void> _redirectToWebCheckout() async {
    final plan = _selected;
    if (plan == null) return;

    final user = _supabase.auth.currentUser;
    final phone = user?.phone ?? '';
    final email = user?.email ?? '';

    final queryParams = <String, String>{
      'type': 'subscription',
      'interval': plan.interval,
      if (phone.isNotEmpty) 'phone': phone,
      if (email.isNotEmpty) 'email': email,
    };

    final uri = Uri.https('lynk-x.app', '/checkout', queryParams);
    await safeLaunchUrl(uri.toString(), mode: LaunchMode.externalApplication);
  }

  // ── feedback helpers ──────────────────────────────────────────────────────

  void _showError(String msg) {
    AppSnackBars.showError(context, msg);
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
          onPressed: () => context.go('/'),
        ),
        title: RepaintBoundary(
          child: SvgPicture.asset(
            'assets/images/official_lynk-x_combined-logo.svg',
            width: 180,
            fit: BoxFit.contain,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.secondary))
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
                backgroundColor: AppColors.secondary,
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
                'Enhance your event experience. Ad-free forums, exclusive badge and early access to every new feature.',
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
                      child: FeatureRow(text: e.value),
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
          ToggleOption(
            label: 'Monthly',
            selected: _interval == 'month',
            onTap: () => setState(() => _interval = 'month'),
          ),
          ToggleOption(
            label: 'Yearly',
            badge: '2 months free',
            selected: _interval == 'year',
            onTap: () => setState(() => _interval = 'year'),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceDisplay(PlanData plan) {
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

  Widget _buildBottomCTA(PlanData plan) {
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
                      : _redirectToWebCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                disabledBackgroundColor:
                    AppColors.secondary.withValues(alpha: 0.3),
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
}

// ── Payment Sheet ─────────────────────────────────────────────────────────────

// ── Sub-widgets ───────────────────────────────────────────────────────────────

// ── Data model ────────────────────────────────────────────────────────────────
