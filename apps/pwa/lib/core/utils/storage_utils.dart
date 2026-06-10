import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

/// Extract storage path from a Supabase public, private, or signed URL.
/// E.g. https://xxxx.supabase.co/storage/v1/object/public/forum_media/forum_uuid/file_uuid.ext
/// Or https://xxxx.supabase.co/storage/v1/object/sign/forum_media/forum_uuid/file_uuid.ext?token=xxxx
/// Returns "forum_uuid/file_uuid.ext".
String getPathFromStorageUrl(String url, String bucket) {
  final uri = Uri.tryParse(url);
  if (uri == null) return '';
  final segments = uri.pathSegments;
  final index = segments.indexOf(bucket);
  if (index != -1 && index + 1 < segments.length) {
    // Exclude query parameters from the last segment if any
    final rawPath = segments.sublist(index + 1).join('/');
    // Uri path segments do not include query parameters, so join is safe.
    return rawPath;
  }
  return '';
}

/// Batch-sign media paths for a given bucket.
/// Returns a map of path -> signedUrl.
Future<Map<String, String>> batchSignStorageUrls(List<String> urls, String bucket, {int expiresIn = 7200}) async {
  if (urls.isEmpty) return {};
  final paths = urls
      .map((u) => getPathFromStorageUrl(u, bucket))
      .where((p) => p.isNotEmpty)
      .toSet()
      .toList();
  if (paths.isEmpty) return {};

  try {
    final signedUrlsResponse = await Supabase.instance.client.storage
        .from(bucket)
        .createSignedUrls(paths, expiresIn);
    
    return {
      for (final item in signedUrlsResponse)
        item.path: item.signedUrl
    };
  } catch (e) {
    debugPrint('[StorageUtils] Error batch signing URLs: $e');
    return {};
  }
}
