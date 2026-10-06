import 'package:lynk_core/core.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'forum_ads_state.dart';

/// Owns banner/interstitial ad state for the forum — semantic matching
/// against the viewed event via pgvector RPC, plus impression/click logging.
/// Every ad shown must come from `match_ad_campaigns` (it carries the serve
/// token that makes the ad billable and attributable to the forum's event and
/// enforces the forum's `has_ads` gate), so when matching is unavailable the
/// forum shows only the built-in upgrade ad rather than reading campaigns
/// directly.
class ForumAdsCubit extends Cubit<ForumAdsState> {
  static const int downloadInterstitialFrequency = 3;
  final String forumId;
  final String userId;
  final String? eventId;
  final DateTime? eventCreatedAt;
  bool isPremium;
  final Set<String> _viewedAds = {};
  final Map<String, Timer> _impressionTimers = {};
  int _downloadCount = 0;

  ForumAdsCubit({
    required this.forumId,
    required this.userId,
    required this.isPremium,
    this.eventId,
    this.eventCreatedAt,
  }) : super(const ForumAdsState());

  bool shouldShowDownloadInterstitial() {
    if (isPremium) return false;
    if (state.interstitialAd == null) return false;
    _downloadCount++;
    return _downloadCount % downloadInterstitialFrequency == 1;
  }

  Future<void> init() async {
    await loadAds();
  }

  Future<void> loadAds() async {
    if (isPremium) {
      if (!isClosed) {
        emit(state.copyWith(ads: [], clearInterstitial: true));
      }
      return;
    }

    if (isClosed) return;
    emit(state.copyWith(isLoading: true));

    try {
      List<dynamic>? embeddingData;
      if (eventId != null && eventCreatedAt != null) {
        embeddingData = await Supabase.instance.client
            .schema('api')
            .rpc('get_event_embedding', params: {
          'p_event_id': eventId,
          'p_created_at': eventCreatedAt!.toIso8601String(),
        });
      }

      if (embeddingData != null) {
        final results = await Future.wait([
          Supabase.instance.client
              .schema('api')
              .rpc('match_ad_campaigns', params: {
            'query_embedding': embeddingData,
            'match_type': 'banner',
            'match_count': 8,
            'p_forum_id': forumId,
          }),
          Supabase.instance.client
              .schema('api')
              .rpc('match_ad_campaigns', params: {
            'query_embedding': embeddingData,
            'match_type': 'interstitial',
            'match_count': 1,
            'p_forum_id': forumId,
          }),
        ]);

        final bannerResults = results[0] as List<dynamic>;
        final interstitialResults = results[1] as List<dynamic>;

        if (!isClosed) {
          final ads =
              bannerResults.map((json) => AdModel.fromMap(json)).toList();
          emit(state.copyWith(
            ads: ads.isEmpty ? _defaultAds : ads,
            interstitialAd: interstitialResults.isNotEmpty
                ? AdModel.fromMap(interstitialResults.first)
                : null,
            clearInterstitial: interstitialResults.isEmpty,
            isLoading: false,
          ));
        }
        return;
      }
    } catch (e, stack) {
      debugPrint('[ForumAdsCubit] Error matching tailored ads: $e\n$stack');
    }

    if (!isClosed) {
      emit(state.copyWith(
        ads: _defaultAds,
        clearInterstitial: true,
        isLoading: false,
      ));
    }
  }

  static const List<AdModel> _defaultAds = [
    AdModel(
      id: 'default_lynk_upgrade',
      title: 'Upgrade to Lynk-X Premium for an ad-free experience!',
      callToAction: 'Upgrade',
      targetUrl: '/subscription',
    ),
  ];

  void logAdImpression(AdModel ad) {
    final adId = ad.id;
    if (adId == 'default_lynk_upgrade') return;
    if (userId == kGuestUserId) return;
    if (_viewedAds.contains(adId)) return;
    if (_impressionTimers.containsKey(adId)) return;

    _impressionTimers[adId] = Timer(const Duration(seconds: 2), () async {
      if (isClosed) return;
      _viewedAds.add(adId);
      _impressionTimers.remove(adId);
      final serveToken = ad.serveToken;
      if (serveToken == null) return;
      try {
        await Supabase.instance.client
            .schema('api')
            .rpc('log_ad_interaction', params: {
          'p_serve_token': serveToken,
          'p_interaction_type': 'impression',
        });
      } catch (e, stack) {
        debugPrint('[ForumAdsCubit] Error logging impression: $e\n$stack');
      }
    });
  }

  void cancelAdImpression(String adId) {
    _impressionTimers[adId]?.cancel();
    _impressionTimers.remove(adId);
  }

  @override
  Future<void> close() {
    for (final timer in _impressionTimers.values) {
      timer.cancel();
    }
    _impressionTimers.clear();
    return super.close();
  }

  Future<void> logAdClick(AdModel ad) async {
    if (ad.id == 'default_lynk_upgrade') return;
    if (userId == kGuestUserId) return;
    final serveToken = ad.serveToken;
    if (serveToken == null) return;
    try {
      await Supabase.instance.client
          .schema('api')
          .rpc('log_ad_interaction', params: {
        'p_serve_token': serveToken,
        'p_interaction_type': 'click',
      });
    } catch (e, stack) {
      debugPrint('[ForumAdsCubit] Error logging click: $e\n$stack');
    }
  }

  Future<void> updatePremiumStatus(bool val) async {
    isPremium = val;
    await loadAds();
  }
}
