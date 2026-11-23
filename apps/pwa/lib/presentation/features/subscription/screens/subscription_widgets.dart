import 'package:material_ui/material_ui.dart';
import 'package:lynk_core/core.dart';

class PaymentSheet extends StatelessWidget {
  final PlanData plan;
  final VoidCallback onWebCheckout;

  const PaymentSheet({
    super.key,
    required this.plan,
    required this.onWebCheckout,
  });

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
            '${plan.currency} ${plan.price.toStringAsFixed(0)} · ${plan.name}',
            style:
                TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
          ),
          const SizedBox(height: 24),

          // ── Web Checkout option (M-Pesa / Card) ──────────────────────
          PaymentOption(
            icon: Icons.payment_outlined,
            title: 'M-Pesa & Online Checkout',
            subtitle: 'Secure checkout on lynk-x.app',
            enabled: true,
            trailing: const Icon(
              Icons.open_in_new,
              color: Colors.white38,
              size: 18,
            ),
            onTap: onWebCheckout,
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

class ToggleOption extends StatelessWidget {
  final String label;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const ToggleOption({super.key, 
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
            color: selected ? AppColors.secondary : Colors.transparent,
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
                        : AppColors.secondary.withValues(alpha: 0.8),
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

class FeatureRow extends StatelessWidget {
  final String text;
  const FeatureRow({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
              color: AppColors.secondary, shape: BoxShape.circle),
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

class PaymentOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final Widget? trailing;
  final VoidCallback onTap;

  const PaymentOption({super.key, 
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

class PlanData {
  final String id;
  final String priceId;
  final String name;
  final String interval;
  final double price;
  final String currency;
  final List<String> features;

  const PlanData({
    required this.id,
    required this.priceId,
    required this.name,
    required this.interval,
    required this.price,
    required this.currency,
    required this.features,
  });

  factory PlanData.fromSupabase(Map<String, dynamic> p, String country) {
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
        .map((pf) => (pf as Map<String, dynamic>)['display_name'] as String? ?? '')
        .where((f) => f.isNotEmpty)
        .toList();

    return PlanData(
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
