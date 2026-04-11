import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_core/core.dart';

/// Subscription upgrade screen.
///
/// Fetches available plans from `subscription_plans` + `subscription_prices`,
/// shows the user's current tier, and lets them select a plan to upgrade.
/// Payment is initiated via an RPC that returns a checkout URL.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSubscribing = false;
  List<_PlanDisplay> _plans = [];
  String? _currentPlanId;
  String? _selectedPlanId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final userId = _supabase.auth.currentUser?.id;

      // Fetch active plans with prices
      final plansData = await _supabase
          .from('subscription_plans')
          .select('id, display_name, description, interval, metadata, subscription_prices(amount, currency)')
          .eq('is_active', true)
          .eq('product_type', 'attendee_premium')
          .order('created_at');

      // Check current subscription
      String? activePlanId;
      if (userId != null) {
        final sub = await _supabase
            .from('subscriptions')
            .select('plan_id')
            .eq('user_id', userId)
            .eq('status', 'active')
            .maybeSingle();

        activePlanId = sub?['plan_id'] as String?;
      }

      final plans = (plansData as List).map((p) {
        final prices = (p['subscription_prices'] as List?) ?? [];
        final firstPrice = prices.isNotEmpty ? prices.first : null;
        final metadata = p['metadata'] as Map<String, dynamic>? ?? {};
        final features =
            (metadata['features'] as List?)?.cast<String>() ?? [];

        return _PlanDisplay(
          id: p['id'] as String,
          name: p['display_name'] as String,
          description: p['description'] as String? ?? '',
          interval: p['interval'] as String? ?? 'month',
          price: firstPrice != null
              ? (firstPrice['amount'] as num).toDouble()
              : 0,
          currency: firstPrice?['currency'] as String? ?? 'KES',
          features: features,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _plans = plans;
          _currentPlanId = activePlanId;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _subscribe(String planId) async {
    setState(() {
      _isSubscribing = true;
      _selectedPlanId = planId;
    });

    try {
      final result = await _supabase.rpc('initiate_subscription', params: {
        'p_plan_id': planId,
      });

      final checkoutUrl = result?['checkout_url'] as String?;
      if (checkoutUrl != null && checkoutUrl.isNotEmpty && mounted) {
        // Payment handled externally — show confirmation
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subscription initiated. Complete payment to activate.'),
          ),
        );
      } else if (mounted) {
        // Direct activation (e.g. free upgrade, wallet payment)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subscription activated!'),
            backgroundColor: Color(0xFF00FF00),
          ),
        );
        _load(); // Refresh to show active state
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to subscribe: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubscribing = false;
          _selectedPlanId = null;
        });
      }
    }
  }

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
        title: const Text(
          'Upgrade Plan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF00)))
          : _plans.isEmpty
              ? _buildNoPlan()
              : _buildPlans(),
    );
  }

  Widget _buildNoPlan() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.workspace_premium,
                size: 64, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              'No plans available',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check back later for premium subscription options.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlans() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Current status banner
          if (_currentPlanId != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF00FF00).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF00FF00).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: Color(0xFF00FF00), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You\'re on the ${_plans.firstWhere((p) => p.id == _currentPlanId, orElse: () => _plans.first).name} plan',
                      style: const TextStyle(
                        color: Color(0xFF00FF00),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.white.withValues(alpha: 0.4), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You\'re on the Free plan. Upgrade to unlock premium features.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Plan cards
          ..._plans.map((plan) => _buildPlanCard(plan)),
        ],
      ),
    );
  }

  Widget _buildPlanCard(_PlanDisplay plan) {
    final isCurrent = plan.id == _currentPlanId;
    final isProcessing = _isSubscribing && _selectedPlanId == plan.id;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isCurrent
            ? const Color(0xFF00FF00).withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? const Color(0xFF00FF00).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.08),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan name + badge
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isCurrent)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF00).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Current',
                    style: TextStyle(
                      color: Color(0xFF00FF00),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Price
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '${plan.currency} ${plan.price.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: ' / ${plan.interval}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          if (plan.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              plan.description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
          ],

          // Features
          if (plan.features.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...plan.features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.check,
                          color: Color(0xFF00FF00), size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          f,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],

          const SizedBox(height: 16),

          // Action button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: isCurrent || _isSubscribing
                  ? null
                  : () => _subscribe(plan.id),
              style: ElevatedButton.styleFrom(
                backgroundColor: isCurrent
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFF00FF00),
                disabledBackgroundColor: isCurrent
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFF00FF00).withValues(alpha: 0.3),
                foregroundColor: isCurrent ? Colors.white38 : Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : Text(
                      isCurrent ? 'Current Plan' : 'Upgrade',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanDisplay {
  final String id;
  final String name;
  final String description;
  final String interval;
  final double price;
  final String currency;
  final List<String> features;

  const _PlanDisplay({
    required this.id,
    required this.name,
    required this.description,
    required this.interval,
    required this.price,
    required this.currency,
    required this.features,
  });
}
