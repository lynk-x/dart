import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/core/utils/image_optimizer.dart';

/// Interactive ad banner carousel with automatic rotation, gesture pause,
/// viewability tracking, and accessibility support.
class AdCarousel extends StatefulWidget {
  final List<AdModel> ads;
  final Function(String)? onAdViewed;
  final Function(String)? onAdViewEnded;
  final Function(AdModel)? onAdClicked;

  const AdCarousel({
    super.key,
    required this.ads,
    this.onAdViewed,
    this.onAdViewEnded,
    this.onAdClicked,
  });

  @override
  State<AdCarousel> createState() => _AdCarouselState();
}

class _AdCarouselState extends State<AdCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  String? _currentAdId;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    if (widget.ads.isNotEmpty) {
      _currentAdId = widget.ads[0].id;
      // Trigger initial view for the first ad after first frame rendering
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _currentAdId != null) {
          widget.onAdViewed?.call(_currentAdId!);
        }
      });
      if (widget.ads.length > 1) {
        _startTimer();
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) return;
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
      }
    });
  }

  void _handlePageChanged(int index) {
    if (index < 0 || index >= widget.ads.length) return;

    // Notify previous ad view ended (cancelling pending 2s impression timer if swiped away early)
    if (_currentAdId != null && _currentAdId != widget.ads[index].id) {
      widget.onAdViewEnded?.call(_currentAdId!);
    }

    setState(() => _currentPage = index);
    _currentAdId = widget.ads[index].id;
    widget.onAdViewed?.call(_currentAdId!);
  }

  @override
  void didUpdateWidget(AdCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ads != oldWidget.ads) {
      _timer?.cancel();
      _timer = null;

      if (widget.ads.isEmpty) {
        if (_currentAdId != null) {
          widget.onAdViewEnded?.call(_currentAdId!);
        }
        _currentPage = 0;
        _currentAdId = null;
      } else {
        if (_currentPage >= widget.ads.length) {
          _currentPage = 0;
          if (_pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        }
        _currentAdId = widget.ads[_currentPage].id;
        if (widget.ads.length > 1) {
          _startTimer();
        }
      }
    }
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
      color: AppColors.surface,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            // Pause timer while user is actively dragging the carousel
            _timer?.cancel();
            _timer = null;
          } else if (notification is ScrollEndNotification) {
            // Resume periodic timer when drag gesture completes
            if (widget.ads.length > 1 && _timer == null) {
              _startTimer();
            }
          }
          return false;
        },
        child: PageView.builder(
          controller: _pageController,
          onPageChanged: _handlePageChanged,
          itemCount: widget.ads.length,
          itemBuilder: (context, index) {
            final ad = widget.ads[index];
            return Semantics(
              button: true,
              label: 'Advertisement: ${ad.title}. Action: ${ad.callToAction}',
              child: GestureDetector(
                onTap: () => widget.onAdClicked?.call(ad),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (ad.imageUrl != null)
                      CachedNetworkImage(
                        imageUrl: ImageOptimizer.getOptimizedUrl(
                          ad.imageUrl!,
                          width: 600,
                          height: 100,
                        ),
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: AppColors.surface),
                        errorWidget: (context, url, err) =>
                            Container(color: AppColors.surface),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.1),
                            Colors.black.withValues(alpha: 0.5),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 0.5),
                            ),
                            child: Text(
                              'AD',
                              style: AppTypography.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ad.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.interTight(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            ad.callToAction.toUpperCase(),
                            style: AppTypography.interTight(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
