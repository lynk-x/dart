import 'package:lynk_core/core.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'forum_ads_state.dart';

class ForumAdsCubit extends Cubit<ForumAdsState> {
  final String forumId;
  final String userId;
  bool isPremium;
  final Set<String> _viewedAds = {};
  final Map<String, Timer> _impressionTimers = {};

  ForumAdsCubit({
    required this.forumId,
    required this.userId,
    required this.isPremium,
  }) : super(const ForumAdsState());

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
      // Composite FK (event_id, event_created_at) can't be auto-embedded by
      // PostgREST, so we fetch the event reference first, then the embedding.
      final forumRow = await Supabase.instance.client
          .schema('social')
          .from('forums')
          .select('event_id, event_created_at')
          .eq('id', forumId)
          .maybeSingle();

      List<dynamic>? embeddingData;
      if (forumRow != null && forumRow['event_id'] != null) {
        final eventRow = await Supabase.instance.client
            .from('events')
            .select('embedding')
            .eq('id', forumRow['event_id'] as String)
            .eq('created_at', forumRow['event_created_at'] as String)
            .maybeSingle();
        embeddingData = eventRow?['embedding'] as List<dynamic>?;
      }

      if (embeddingData != null) {
        final results = await Future.wait([
          Supabase.instance.client.rpc('match_ad_campaigns', params: {
            'query_embedding': embeddingData,
            'match_type': 'banner',
            'match_count': 8,
          }),
          Supabase.instance.client.rpc('match_ad_campaigns', params: {
            'query_embedding': embeddingData,
            'match_type': 'interstitial',
            'match_count': 1,
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
      // Fallback to latest active ads if matching fails
    }

    try {
      final now = DateTime.now().toIso8601String();
      final results = await Future.wait([
        Supabase.instance.client
            .schema('api')
            .from('v1_ad_campaigns')
            .select('*')
            .eq('status', 'active')
            .eq('type', 'banner')
            .lte('start_at', now)
            .gte('end_at', now)
            .order('created_at', ascending: false)
            .limit(8),
        Supabase.instance.client
            .schema('api')
            .from('v1_ad_campaigns')
            .select('*')
            .eq('status', 'active')
            .eq('type', 'interstitial')
            .lte('start_at', now)
            .gte('end_at', now)
            .order('created_at', ascending: false)
            .limit(1),
      ]);

      final bannerData = results[0] as List<dynamic>;
      final interstitialData = results[1] as List<dynamic>;

      final validBanners =
          bannerData.map((json) => AdModel.fromMap(json)).toList();

      AdModel? validInterstitial;
      if (interstitialData.isNotEmpty) {
        validInterstitial = AdModel.fromMap(interstitialData.first);
      }

      if (!isClosed) {
        emit(state.copyWith(
          ads: validBanners.isEmpty ? _defaultAds : validBanners,
          interstitialAd: validInterstitial,
          clearInterstitial: validInterstitial == null,
          isLoading: false,
        ));
      }
    } catch (e, stack) {
      debugPrint('[ForumAdsCubit] Error grouping ads: $e\n$stack');
      if (!isClosed) {
        emit(state.copyWith(
          ads: _defaultAds,
          isLoading: false,
        ));
      }
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

  void logAdImpression(String adId) {
    if (adId == 'default_lynk_upgrade') return;
    if (userId == kGuestUserId) return;
    if (_viewedAds.contains(adId)) return;
    if (_impressionTimers.containsKey(adId)) return;

    _impressionTimers[adId] = Timer(const Duration(seconds: 2), () async {
      if (isClosed) return;
      _viewedAds.add(adId);
      _impressionTimers.remove(adId);
      try {
        await Supabase.instance.client.rpc('log_ad_interaction', params: {
          'p_campaign_id': adId,
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

  Future<void> logAdClick(String adId) async {
    if (adId == 'default_lynk_upgrade') return;
    if (userId == kGuestUserId) return;
    try {
      await Supabase.instance.client.rpc('log_ad_interaction', params: {
        'p_campaign_id': adId,
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
