import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lynk_core/core.dart';

class PaymentSheet extends StatefulWidget {
  final PlanData plan;
  final double walletBalance;
  final String walletCurrency;
  final bool walletSufficient;
  final VoidCallback onWallet;
  final VoidCallback onTopUp;
  final Future<void> Function(String phone) onMpesa;

  const PaymentSheet({super.key, 
    required this.plan,
    required this.walletBalance,
    required this.walletCurrency,
    required this.walletSufficient,
    required this.onWallet,
    required this.onTopUp,
    required this.onMpesa,
  });

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
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
          PaymentOption(
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
                  foregroundColor: AppColors.secondary,
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
                PaymentOption(
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
