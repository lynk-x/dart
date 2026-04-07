import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';

class AdCarousel extends StatefulWidget {
  final List<AdModel> ads;
  final Function(String)? onAdViewed;
  final Function(AdModel)? onAdClicked;

  const AdCarousel({
    super.key,
    required this.ads,
    this.onAdViewed,
    this.onAdClicked,
  });

  @override
  State<AdCarousel> createState() => _AdCarouselState();
}

class _AdCarouselState extends State<AdCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    if (widget.ads.isNotEmpty) {
      // Trigger initial view for the first ad.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onAdViewed?.call(widget.ads[0].id);
      });
      if (widget.ads.length > 1) {
        _startTimer();
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_currentPage < widget.ads.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
        widget.onAdViewed?.call(widget.ads[_currentPage].id);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ads.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 50,
      color: const Color(0xFF1E1E1E),
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentPage = index),
        itemCount: widget.ads.length,
        itemBuilder: (context, index) {
          final ad = widget.ads[index];
          return GestureDetector(
            onTap: () => widget.onAdClicked?.call(ad),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    ad.title,
                    style: AppTypography.inter(
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    ad.callToAction,
                    style: AppTypography.interTight(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
