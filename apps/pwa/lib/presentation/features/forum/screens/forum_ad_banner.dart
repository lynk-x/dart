import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_ads_cubit.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/widgets/ad_carousel.dart';

/// The forum's sponsor carousel with impression/click logging wired to ForumAdsCubit. Its own
/// widget (instead of inline in the screen) so the click handling lives in one readable place.
class ForumAdBanner extends StatelessWidget {
  final List<AdModel> ads;
  const ForumAdBanner({super.key, required this.ads});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AdCarousel(
        ads: ads,
        onAdViewed: (ad) => context
            .read<ForumAdsCubit>()
            .logAdImpression(ad),
        onAdViewEnded: (adId) =>
            context
                .read<
                    ForumAdsCubit>()
                .cancelAdImpression(
                    adId),
        onAdClicked: (ad) async {
          context
              .read<ForumAdsCubit>()
              .logAdClick(ad);
          if (ad.targetUrl !=
              null) {
            final uri = Uri.parse(
                ad.targetUrl!);
            if (await canLaunchUrl(
                uri)) {
              await launchUrl(uri);
            }
          } else if (ad
                  .targetEventId !=
              null) {
            context.push(
                '/events/${ad.targetEventId}');
          }
        },
      ),
    );
  }
}
