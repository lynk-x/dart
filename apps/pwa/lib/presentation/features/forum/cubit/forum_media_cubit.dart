import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'forum_media_state.dart';

class ForumMediaCubit extends Cubit<ForumMediaState> {
  static const _uuid = Uuid();
  final String forumId;
  final String userId;
  final bool isOrganizer;

  ForumMediaCubit({
    required this.forumId,
    required this.userId,
    required this.isOrganizer,
  }) : super(const ForumMediaState());

  Future<void> init() async {
    await refreshMedia();
  }

  Future<void> refreshMedia() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true));
    try {
      var query = Supabase.instance.client
          .from('forum_media')
          .select()
          .eq('forum_id', forumId);

      if (!isOrganizer) {
        query = query.eq('is_approved', true);
      }

      final data = await query.order('created_at', ascending: false).limit(21);
      final media = data.map((json) => ForumMedia.fromMap(json)).toList();

      if (!isClosed) {
        emit(state.copyWith(mediaItems: media, isLoading: false));
      }
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] Error: $e\n$stack');
      if (!isClosed) {
        emit(state.copyWith(isLoading: false, error: e.toString()));
      }
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || isClosed) return;
    emit(state.copyWith(isLoading: true));
    final startIndex = state.mediaItems.length;
    try {
      var query = Supabase.instance.client
          .from('forum_media')
          .select()
          .eq('forum_id', forumId);

      if (!isOrganizer) {
        query = query.eq('is_approved', true);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(startIndex, startIndex + 20);

      final more = data.map((json) => ForumMedia.fromMap(json)).toList();

      if (!isClosed) {
        emit(state.copyWith(
          mediaItems: [...state.mediaItems, ...more],
          isLoading: false,
        ));
      }
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] Error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> uploadMedia({
    required File file,
    required String type,
    required String mimeType,
  }) async {
    if (isClosed) return;
    emit(state.copyWith(isUploading: true));
    try {
      final ext = file.path.split('.').last;
      final fileId = _uuid.v4();
      final fileName = '$fileId.$ext';
      final path = '$forumId/$fileName';

      await Supabase.instance.client.storage
          .from('forum_media')
          .upload(path, file, fileOptions: FileOptions(contentType: mimeType));

      final publicUrl = Supabase.instance.client.storage
          .from('forum_media')
          .getPublicUrl(path);

      String? thumbnailPublicUrl;
      try {
        final tempDir = await getTemporaryDirectory();
        final thumbPath = '${tempDir.path}/thumb_$fileName.jpg';
        File? thumbFile;

        if (type == 'image') {
          final result = await FlutterImageCompress.compressAndGetFile(
            file.absolute.path,
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

        if (thumbFile != null) {
          final thumbName = 'thumbnails/$fileId.jpg';
          await Supabase.instance.client.storage.from('forum_media').upload(
                thumbName,
                thumbFile,
                fileOptions: const FileOptions(contentType: 'image/jpeg'),
              );
          thumbnailPublicUrl = Supabase.instance.client.storage
              .from('forum_media')
              .getPublicUrl(thumbName);
        }
      } catch (e, stack) {
      debugPrint('[ForumMediaCubit] Error: $e\n$stack');
        // Thumbnail generation failed, proceed without it
      }

      await Supabase.instance.client.from('forum_media').insert({
        'id': fileId,
        'forum_id': forumId,
        'uploader_id': userId,
        'url': publicUrl,
        'thumbnail_url': thumbnailPublicUrl,
        'media_type': type,
        'mime_type': mimeType,
        'file_size': await file.length(),
        'is_approved': isOrganizer,
      });

      if (!isClosed) {
        emit(state.copyWith(isUploading: false));
        await refreshMedia();
      }
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] Error: $e\n$stack');
      if (!isClosed) {
        emit(state.copyWith(isUploading: false, error: e.toString()));
      }
    }
  }

  Future<void> approveMedia(String mediaId) async {
    if (!isOrganizer) return;
    try {
      await Supabase.instance.client
          .from('forum_media')
          .update({'is_approved': true}).eq('id', mediaId);
      await refreshMedia();
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] Error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> deleteMedia(String mediaId) async {
    if (!isOrganizer) return;
    try {
      await Supabase.instance.client
          .from('forum_media')
          .delete()
          .eq('id', mediaId);
      await refreshMedia();
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] Error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(error: e.toString()));
    }
  }

  void clearError() {
    emit(state.copyWith(clearError: true));
  }
}
