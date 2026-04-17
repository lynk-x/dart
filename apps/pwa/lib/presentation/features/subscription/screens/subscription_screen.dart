import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
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

      // Fetch active plans with prices and normalized features
      final plansData = await _supabase
          .from('subscription_plans')
          .select('id, display_name, description, interval, metadata, subscription_prices(amount, currency), plan_features(subscription_features(display_name))')
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
        
        // Fetch features from the join
        final planFeaturesRaw = (p['plan_features'] as List?) ?? [];
        final List<String> features = planFeaturesRaw.map((pf) {
          final sf = pf['subscription_features'] as Map<String, dynamic>?;
          return sf?['display_name'] as String? ?? '';
        }).where((f) => f.isNotEmpty).toList();

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
        final uri = Uri.parse(checkoutUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open payment page.')),
          );
        }
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
        title: Image.asset(
          'assets/images/lynk-x_combined-logo.png',
          width: 180,
          fit: BoxFit.contain,
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _plans.isEmpty
              ? _buildNoPlan()
              : _buildUpgradeContent(),
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
            const Text(
              'No plans available',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradeContent() {
    // We prioritize the attendee_premium plan (usually the only one)
    final plan = _plans.firstWhere((p) => p.name.contains('Premium'), orElse: () => _plans.first);
    final isCurrent = plan.id == _currentPlanId;
    final isProcessing = _isSubscribing && _selectedPlanId == plan.id;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Icon Wrapper (Polygon Star)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.star_rounded,
              size: 56,
              color: AppColors.secondary,
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Title
          const Text(
            'Lynk-X Premium',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Description
          Text(
            'Enhance your event experience. Get access to ad-free forums, exclusive badges, and seamless interactions across all your limits forever.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 15,
              height: 1.5,
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Benefits Container
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                if (plan.features.isEmpty) ...[
                  Center(
                    child: Text(
                      'Feature details not available.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
                    ),
                  ),
                ] else
                  ...plan.features.asMap().entries.map((entry) {
                    final isLast = entry.key == plan.features.length - 1;
                    return Column(
                      children: [
                        _buildBenefitRow(entry.value),
                        if (!isLast) const SizedBox(height: 16),
                      ],
                    );
                  }),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Price
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${plan.currency} ${plan.price.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                ' / ${plan.interval}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 16,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 32),
          
          // Subscribe Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: isCurrent || _isSubscribing
                  ? null
                  : () => _showSubscribeConfirmation(plan),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.3),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: isProcessing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : Text(
                      isCurrent ? 'Current Plan' : 'Upgrade Now',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Terms
          Text(
            'By upgrading, you agree to our Terms of Service. This is a recurring subscription which you can cancel securely at any time.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _showSubscribeConfirmation(_PlanDisplay plan) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Confirm Upgrade',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildConfirmRow('Plan', plan.name),
            const SizedBox(height: 10),
            _buildConfirmRow(
              'Amount',
              '${plan.currency} ${plan.price.toStringAsFixed(2)} / ${plan.interval}',
            ),
            const SizedBox(height: 10),
            _buildConfirmRow('Billing', 'Recurring — cancel anytime'),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _subscribe(plan.id);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                minimumSize: const Size.fromHeight(52),
                elevation: 0,
              ),
              child: const Text(
                'Confirm & Pay',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildBenefitRow(String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, size: 14, color: Colors.black),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
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
