import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

class _CachedSignedUrl {
  final String signedUrl;
  final DateTime expiresAt;

  _CachedSignedUrl(this.signedUrl, this.expiresAt);

  bool get isValid => DateTime.now().isBefore(expiresAt);
}

final Map<String, _CachedSignedUrl> _signedUrlCache = {};

/// Batch-sign media paths using the media-signer Edge Function.
/// Returns a map of path -> signedUrl.
///
/// Implements an in-memory cache with expiration buffer to prevent redundant
/// network round-trips for already-signed URLs.
Future<Map<String, String>> batchSignStorageUrls(List<String> urls, String bucket, {int expiresIn = 3600}) async {
  if (urls.isEmpty) return {};
  final paths = urls
      .map((u) => getPathFromStorageUrl(u, bucket))
      .where((p) => p.isNotEmpty)
      .toSet()
      .toList();
  if (paths.isEmpty) return {};

  final resultMap = <String, String>{};
  final uncachedPaths = <String>[];

  // 1. Check in-memory cache for valid non-expired signed URLs
  for (final path in paths) {
    final cached = _signedUrlCache[path];
    if (cached != null && cached.isValid) {
      resultMap[path] = cached.signedUrl;
    } else {
      uncachedPaths.add(path);
    }
  }

  // 2. Return early if all paths were served from cache
  if (uncachedPaths.isEmpty) {
    return resultMap;
  }

  try {
    final response = await Supabase.instance.client.functions.invoke(
      'media-signer',
      body: {
        'action': 'sign_read_batch',
        'fileKeys': uncachedPaths,
      },
    );

    if (response.status != 200) {
      debugPrint('[StorageUtils] Edge function returned status ${response.status}');
      return resultMap;
    }

    final data = response.data;
    if (data == null || data['signedUrls'] == null) {
      return resultMap;
    }

    final newSignedUrls = Map<String, String>.from(data['signedUrls']);
    // Cache valid for (expiresIn - 10 minutes) buffer to avoid race conditions
    final ttlSeconds = (expiresIn - 600).clamp(60, expiresIn);
    final expiresAt = DateTime.now().add(Duration(seconds: ttlSeconds));

    newSignedUrls.forEach((path, signedUrl) {
      _signedUrlCache[path] = _CachedSignedUrl(signedUrl, expiresAt);
      resultMap[path] = signedUrl;
    });

    return resultMap;
  } catch (e) {
    debugPrint('[StorageUtils] Error batch signing URLs via Edge Function: $e');
    return resultMap;
  }
}

/// Requests a signed upload URL from the media-signer Edge Function, then
/// PUTs [bytes] directly to R2. Returns the resulting file key (storage path)
/// on success, or throws on failure.
Future<String> uploadToStorage({
  required List<int> bytes,
  required String filename,
  required String contentType,
  required String folder,
  String mediaType = 'image',
}) async {
  final signResponse = await Supabase.instance.client.functions.invoke(
    'media-signer',
    body: {
      'action': 'upload',
      'folder': folder,
      'filename': filename,
      'contentType': contentType,
      'mediaType': mediaType,
    },
  );

  final signData = signResponse.data;
  final uploadUrl = signData?['uploadUrl'] as String?;
  final fileKey = signData?['fileKey'] as String?;
  if (signResponse.status != 200 || uploadUrl == null || fileKey == null) {
    throw Exception('Failed to get upload URL');
  }

  final putResponse = await http.put(
    Uri.parse(uploadUrl),
    headers: {'Content-Type': contentType},
    body: bytes,
  );

  if (putResponse.statusCode < 200 || putResponse.statusCode >= 300) {
    throw Exception('Failed to upload document');
  }

  return fileKey;
}
