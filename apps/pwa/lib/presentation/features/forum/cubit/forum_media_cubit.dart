import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'forum_media_state.dart';

// flutter_image_compress, video_thumbnail, and path_provider have no web
// support. Thumbnail generation is skipped on web; on mobile it remains
// available via the conditional import below.
import 'forum_media_cubit_thumbnail_stub.dart'
    if (dart.library.io) 'forum_media_cubit_thumbnail_mobile.dart';

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
    required XFile file,
    required String type,
    required String mimeType,
  }) async {
    if (isClosed) return;
    emit(state.copyWith(isUploading: true));
    try {
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last.toLowerCase();
      final fileId = _uuid.v4();
      final fileName = '$fileId.$ext';
      final path = '$forumId/$fileName';

      await Supabase.instance.client.storage
          .from('forum_media')
          .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mimeType));

      final publicUrl = Supabase.instance.client.storage
          .from('forum_media')
          .getPublicUrl(path);

      // Thumbnail generation uses dart:io APIs — skipped on web.
      String? thumbnailPublicUrl;
      if (!kIsWeb) {
        try {
          thumbnailPublicUrl = await generateThumbnail(
            file: file,
            type: type,
            fileId: fileId,
            forumId: forumId,
          );
        } catch (e) {
          debugPrint('[ForumMediaCubit] Thumbnail generation failed: $e');
        }
      }

      await Supabase.instance.client.from('forum_media').insert({
        'id': fileId,
        'forum_id': forumId,
        'uploader_id': userId,
        'url': publicUrl,
        'thumbnail_url': thumbnailPublicUrl,
        'media_type': type,
        'mime_type': mimeType,
        'file_size': bytes.length,
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
