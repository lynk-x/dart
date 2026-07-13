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
