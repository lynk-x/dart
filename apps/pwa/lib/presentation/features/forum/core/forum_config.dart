/// Centralized operational constants and thresholds for the Lynk-X Forum module
abstract class ForumConfig {
  /// Maximum number of image URLs cached in memory during media pre-caching
  static const int maxPrecachedMediaUrls = 20;

  /// Maximum string length scanned for URL/mention regexes to prevent Client DoS
  static const int maxRegexScanLength = 5000;

  /// Maximum decoded bitmap memory limit in MB for PaintingBinding imageCache
  static const int maxDecodedImageCacheMb = 30;

  /// Maximum number of items in PaintingBinding imageCache
  static const int maxDecodedImageCount = 50;

  /// Fallback timeout (in milliseconds) before recorded Blob Object URLs are auto-revoked
  static const int autoRevokeBlobTimeoutMs = 60000;

  // ---------------------------------------------------------------------------
  // Tab layout helpers
  // ---------------------------------------------------------------------------

  /// Returns the absolute PageView index for the Media tab based on which
  /// other tabs are enabled. Centralizes the calculation to prevent the
  /// "showUpdates ? 1 : 0" + "showChat ? 1 : 0" pattern being duplicated
  /// across [ForumView._buildTabs], [ForumView._isMediaTabActive], and
  /// anywhere else tab indices are resolved.
  static int mediaTabIndex({
    required bool showUpdates,
    required bool showChat,
  }) =>
      (showUpdates ? 1 : 0) + (showChat ? 1 : 0);

  // ---------------------------------------------------------------------------
  // Ad-visibility helper
  // ---------------------------------------------------------------------------

  /// Single source of truth for whether the banner ad carousel should be
  /// rendered. Prevents the identical 4-condition expression from being
  /// copy-pasted into both the sliver header builder and the stage body.
  ///
  /// [isPremium]     — user/event has a premium subscription (ads suppressed).
  /// [bannerEnabled] — `enable_banner_ad` feature flag.
  /// [forumAdsEnabled] — `enable_forum_ads` feature flag.
  /// [hasAdsContent] — the [ForumAdsState.ads] list is non-empty.
  static bool showBannerAd({
    required bool isPremium,
    required bool bannerEnabled,
    required bool forumAdsEnabled,
    required bool hasAdsContent,
  }) =>
      !isPremium && bannerEnabled && forumAdsEnabled && hasAdsContent;
}
