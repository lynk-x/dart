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
}
