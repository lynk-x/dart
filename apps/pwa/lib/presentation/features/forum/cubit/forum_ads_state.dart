import 'package:equatable/equatable.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';

class ForumAdsState extends Equatable {
  final List<AdModel> ads;
  final AdModel? interstitialAd;
  final bool isLoading;

  const ForumAdsState({
    this.ads = const [],
    this.interstitialAd,
    this.isLoading = false,
  });

  ForumAdsState copyWith({
    List<AdModel>? ads,
    AdModel? interstitialAd,
    bool? isLoading,
    bool clearInterstitial = false,
  }) {
    return ForumAdsState(
      ads: ads ?? this.ads,
      interstitialAd:
          clearInterstitial ? null : interstitialAd ?? this.interstitialAd,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [ads, interstitialAd, isLoading];
}
