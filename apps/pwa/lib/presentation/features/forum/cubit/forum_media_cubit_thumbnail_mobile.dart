import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Mobile-only: generates a compressed thumbnail and uploads it, returning the
// public URL. Returns null if generation fails or the file type is unsupported.
Future<String?> generateThumbnail({
  required XFile file,
  required String type,
  required String fileId,
  required String forumId,
}) async {
  final tempDir = await getTemporaryDirectory();
  final thumbPath = '${tempDir.path}/thumb_$fileId.jpg';
  File? thumbFile;

  if (type == 'image') {
    final result = await FlutterImageCompress.compressAndGetFile(
      file.path,
      thumbPath,
      quality: 70,
      minWidth: 400,
      minHeight: 400,
    );
    if (result != null) thumbFile = File(result.path);
  } else if (type == 'video') {
    final result = await VideoThumbnail.thumbnailFile(
      video: file.path,
      thumbnailPath: thumbPath,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 400,
      quality: 70,
    );
    if (result != null) thumbFile = File(result);
  }

  if (thumbFile == null) return null;

  final thumbName = 'thumbnails/$fileId.jpg';
  await Supabase.instance.client.storage.from('forum_media').upload(
        thumbName,
        thumbFile,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );

  return Supabase.instance.client.storage
      .from('forum_media')
      .getPublicUrl(thumbName);
}
