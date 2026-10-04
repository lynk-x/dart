import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Shared `flutter_cache_manager` instance used for cached network images
/// app-wide, so all consumers share one disk cache rather than each
/// defaulting to its own.
class LynkCacheManager {
  static const key = 'lynkCacheKey';

  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 200,
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );
}
