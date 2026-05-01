import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'forum_media_state.dart';

class ForumMediaCubit extends HydratedCubit<ForumMediaState> {
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
          .schema('forum_media').from('forum_media')
          .select()
          .eq('forum_id', forumId);

      if (!isOrganizer) {
        query = query.eq('is_approved', true);
      }

      final data = await query.order('created_at', ascending: false).limit(20);
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
    if (state.isLoading || state.isUploading || isClosed) return;
    emit(state.copyWith(isLoading: true));
    final startIndex = state.mediaItems.length;
    try {
      var query = Supabase.instance.client
          .schema('forum_media').from('forum_media')
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

  /// Uploads multiple media items to Supabase.
  Future<void> uploadMultipleMedia({
    required List<XFile> files,
    required String type,
  }) async {
    if (isClosed || files.isEmpty) return;
    emit(state.copyWith(isUploading: true));
    try {
      for (final file in files) {
        final bytes = await file.readAsBytes();
        final ext = file.name.split('.').last.toLowerCase();
        final fileId = _uuid.v4();
        final fileName = '$fileId.$ext';
        final path = '$forumId/$fileName';
        final mimeType = type == 'video' ? 'video/$ext' : 'image/$ext';

        await Supabase.instance.client.storage
            .from('forum_media')
            .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mimeType));

        final publicUrl = Supabase.instance.client.storage
            .from('forum_media')
            .getPublicUrl(path);

        await Supabase.instance.client.schema('forum_media').from('forum_media').insert({
          'id': fileId,
          'forum_id': forumId,
          'uploader_id': userId,
          'url': publicUrl,
          'media_type': type,
          'mime_type': mimeType,
          'file_size': bytes.length,
          'is_approved': isOrganizer,
        });
      }

      if (!isClosed) {
        emit(state.copyWith(isUploading: false));
        await refreshMedia();
      }
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] Multi-upload error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(isUploading: false, error: e.toString()));
      rethrow;
    }
  }

  /// Uploads a single media file to Supabase.
  Future<void> uploadMedia({
    required XFile file,
    required String type,
    required String mimeType,
  }) async {
    await uploadMultipleMedia(files: [file], type: type);
  }

  Future<void> approveMedia(String mediaId) async {
    if (!isOrganizer) return;
    try {
      await Supabase.instance.client
          .schema('forum_media').from('forum_media')
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
          .schema('forum_media').from('forum_media')
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

  @override
  ForumMediaState? fromJson(Map<String, dynamic> json) => ForumMediaState.fromMap(json);

  @override
  Map<String, dynamic>? toJson(ForumMediaState state) => state.toJson();

  @override
  String get id => forumId;
}
