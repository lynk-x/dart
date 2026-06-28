import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

/// Extract storage path from a URL or key, keeping the bucket/folder prefix.
/// E.g. https://xxxx.supabase.co/storage/v1/object/public/forum_media/forum_uuid/file_uuid.ext -> "forum_media/forum_uuid/file_uuid.ext"
/// Or https://cdn.lynk-x.app/forum_media/forum_uuid/file_uuid.ext -> "forum_media/forum_uuid/file_uuid.ext"
/// Or "forum_media/forum_uuid/file_uuid.ext" -> "forum_media/forum_uuid/file_uuid.ext"
String getPathFromStorageUrl(String url, String bucket) {
  if (url.isEmpty) return '';

  if (url.startsWith('$bucket/')) {
    return url;
  }

  final uri = Uri.tryParse(url);
  if (uri == null) return '';
  
  final segments = uri.pathSegments;
  final index = segments.indexOf(bucket);
  if (index != -1) {
    return segments.sublist(index).join('/');
  }
  
  return '';
}

/// Batch-sign media paths using the media-signer Edge Function.
/// Returns a map of path -> signedUrl.
Future<Map<String, String>> batchSignStorageUrls(List<String> urls, String bucket, {int expiresIn = 3600}) async {
  if (urls.isEmpty) return {};
  final paths = urls
      .map((u) => getPathFromStorageUrl(u, bucket))
      .where((p) => p.isNotEmpty)
      .toSet()
      .toList();
  if (paths.isEmpty) return {};

  try {
    final response = await Supabase.instance.client.functions.invoke(
      'media-signer',
      body: {
        'action': 'sign_read_batch',
        'fileKeys': paths,
      },
    );

    if (response.status != 200) {
      debugPrint('[StorageUtils] Edge function returned status ${response.status}');
      return {};
    }

    final data = response.data;
    if (data == null || data['signedUrls'] == null) {
      return {};
    }

    return Map<String, String>.from(data['signedUrls']);
  } catch (e) {
    debugPrint('[StorageUtils] Error batch signing URLs via Edge Function: $e');
    return {};
  }
}
