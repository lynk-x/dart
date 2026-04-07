import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';

class InterstitialAd extends StatefulWidget {
  final VoidCallback onClose;
  final AdModel ad;

  const InterstitialAd({
    super.key,
    required this.onClose,
    required this.ad,
  });

  @override
  State<InterstitialAd> createState() => _InterstitialAdState();
}

class _InterstitialAdState extends State<InterstitialAd> {
  int _secondsRemaining = 5;
  Timer? _timer;
  bool _canClose = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _logImpression();
  }

  void _logImpression() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      Supabase.instance.client.from('ad_analytics').insert({
        'campaign_id': widget.ad.id,
        'interaction_type': 'impression',
        'user_id': userId,
      }).catchError((_) {});
    }
  }

  void _logClickAndNavigate() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      Supabase.instance.client.from('ad_analytics').insert({
        'campaign_id': widget.ad.id,
        'interaction_type': 'click',
        'user_id': userId,
      }).catchError((_) {});
    }

    if (widget.ad.targetUrl != null) {
      final uri = Uri.parse(widget.ad.targetUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        setState(() {
          _canClose = true;
        });
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.ad.title,
                      style: AppTypography.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    'Download in progress',
                    style: AppTypography.inter(
                      fontSize: 14,
                      color: AppColors.primaryText,
                    ),
                  ),
                  _canClose
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: widget.onClose,
                        )
                      : Text(
                          _secondsRemaining.toString().padLeft(2, '0'),
                          style: AppTypography.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ],
              ),
            ),
            // AD Content
            Expanded(
              child: GestureDetector(
                onTap: _logClickAndNavigate,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.ad.imageUrl != null)
                      Image.network(
                        widget.ad.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const EmptyState(
                            message: 'Ad content loading failed'),
                      )
                    else
                      const EmptyState(message: 'No ad material'),
                    // CTA Button overlay
                    Positioned(
                      bottom: 40,
                      left: 20,
                      right: 20,
                      child: ElevatedButton(
                        onPressed: _logClickAndNavigate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          widget.ad.callToAction,
                          style: AppTypography.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
