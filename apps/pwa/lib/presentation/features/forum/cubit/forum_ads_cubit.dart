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
      // Priority: Recommendation-based ads (based on event embedding)
      final forumData = await Supabase.instance.client
          .from('forums')
          .select('events(embedding)')
          .eq('id', forumId)
          .single();

      final List<dynamic>? embeddingData =
          forumData['events']?['embedding'] as List<dynamic>?;

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
          emit(state.copyWith(
            ads: bannerResults.map((json) => AdModel.fromMap(json)).toList(),
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
            .from('ad_campaigns')
            .select('*, ad_assets(*)')
            .eq('status', 'active')
            .eq('type', 'banner')
            .lte('start_at', now)
            .gte('end_at', now)
            .order('created_at', ascending: false)
            .limit(8),
        Supabase.instance.client
            .from('ad_campaigns')
            .select('*, ad_assets(*)')
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
          ads: validBanners,
          interstitialAd: validInterstitial,
          clearInterstitial: validInterstitial == null,
          isLoading: false,
        ));
      }
    } catch (e, stack) {
      debugPrint('[ForumAdsCubit] Error grouping ads: $e\n$stack');
      if (!isClosed) emit(state.copyWith(isLoading: false));
    }
  }

  void logAdImpression(String adId) {
    if (userId == kGuestUserId) return;
    if (_viewedAds.contains(adId)) return;
    if (_impressionTimers.containsKey(adId)) return;

    _impressionTimers[adId] = Timer(const Duration(seconds: 2), () async {
      if (isClosed) return;
      _viewedAds.add(adId);
      _impressionTimers.remove(adId);
      try {
        await Supabase.instance.client.from('ad_analytics').insert({
          'campaign_id': adId,
          'interaction_type': 'impression',
          'user_id': userId,
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
    if (userId == kGuestUserId) return;
    try {
      await Supabase.instance.client.from('ad_analytics').insert({
        'campaign_id': adId,
        'interaction_type': 'click',
        'user_id': userId,
      });
    } catch (e, stack) {
      debugPrint('[ForumAdsCubit] Error logging click: $e\n$stack');
    }
  }

  void updatePremiumStatus(bool val) {
    isPremium = val;
    loadAds();
  }
}
