import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/core/utils/storage_utils.dart';
import 'package:lynk_x/data/repositories/forum_repository.dart';
import 'forum_media_state.dart';

class ForumMediaCubit extends HydratedCubit<ForumMediaState> {
  static const _uuid = Uuid();
  final String forumId;
  final String userId;
  final bool isOrganizer;
  final bool isModerator;
  final ForumRepository repo;
  RealtimeChannel? _mediaSubscription;

  bool get isModeratorOrOrganizer => isOrganizer || isModerator;

  List<ForumMedia> _sortMedia(List<ForumMedia> items) {
    return List<ForumMedia>.from(items)
      ..sort((a, b) {
        if (a.isApproved != b.isApproved) {
          return a.isApproved ? 1 : -1;
        }
        return b.createdAt.compareTo(a.createdAt);
      });
  }

  ForumMediaCubit({
    required this.forumId,
    required this.userId,
    required this.isOrganizer,
    required this.isModerator,
    required this.repo,
  }) : super(const ForumMediaState());

  Future<void> init() async {
    await refreshMedia();
    _setupRealtimeListener();
  }

  void _setupRealtimeListener() {
    _mediaSubscription = repo.subscribeToMediaChanges(forumId, (payload) async {
      if (payload.eventType == PostgresChangeEvent.insert) {
        final data = payload.newRecord;
        final mediaItem = ForumMedia.fromMap(data);

        // Deduplicate
        if (state.mediaItems.any((m) => m.id == mediaItem.id)) return;

        // Filter permissions: General users only see approved media
        if (!isModeratorOrOrganizer && !mediaItem.isApproved) return;

        // Sign URL on-the-fly
        final path = getPathFromStorageUrl(mediaItem.url, 'forum_media');
        final signedMap = await batchSignStorageUrls([mediaItem.url], 'forum_media');
        final signed = signedMap[path];

        final finalItem = signed != null
            ? mediaItem.copyWith(url: signed, thumbnailUrl: signed)
            : mediaItem;

        if (!isClosed) {
          final updatedItems = [finalItem, ...state.mediaItems];
          emit(state.copyWith(mediaItems: _sortMedia(updatedItems)));
        }
      } else if (payload.eventType == PostgresChangeEvent.update) {
        final data = payload.newRecord;
        final mediaItem = ForumMedia.fromMap(data);

        if (!isModeratorOrOrganizer && !mediaItem.isApproved) {
          // If it got unapproved/rejected, remove it for general users
          final updated = state.mediaItems.where((m) => m.id != mediaItem.id).toList();
          if (!isClosed) emit(state.copyWith(mediaItems: _sortMedia(updated)));
        } else {
          // Update approval status or metadata in-place
          final index = state.mediaItems.indexWhere((m) => m.id == mediaItem.id);
          if (index != -1) {
            final updatedList = List<ForumMedia>.from(state.mediaItems);
            final existing = updatedList[index];
            // Preserve already signed URLs if urls haven't changed path
            updatedList[index] = mediaItem.copyWith(
              url: existing.url,
              thumbnailUrl: existing.thumbnailUrl,
            );
            if (!isClosed) emit(state.copyWith(mediaItems: _sortMedia(updatedList)));
          } else if (mediaItem.isApproved || isModeratorOrOrganizer) {
            // If newly approved/visible, fetch signed URL and prepend
            final path = getPathFromStorageUrl(mediaItem.url, 'forum_media');
            final signedMap = await batchSignStorageUrls([mediaItem.url], 'forum_media');
            final signed = signedMap[path];
            final finalItem = signed != null
                ? mediaItem.copyWith(url: signed, thumbnailUrl: signed)
                : mediaItem;

            if (!isClosed) {
              final updatedItems = [finalItem, ...state.mediaItems];
              emit(state.copyWith(mediaItems: _sortMedia(updatedItems)));
            }
          }
        }
      } else if (payload.eventType == PostgresChangeEvent.delete) {
        final id = payload.oldRecord['id'] as String?;
        final updated = state.mediaItems.where((m) => m.id != id).toList();
        if (!isClosed) emit(state.copyWith(mediaItems: _sortMedia(updated)));
      }
    });
    _mediaSubscription?.subscribe();
  }

  Future<void> refreshMedia() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true));
    try {
      var query = Supabase.instance.client
          .schema('api').from('v1_forum_media')
          .select()
          .eq('forum_id', forumId);

      if (!isModeratorOrOrganizer) {
        query = query.eq('is_approved', true);
      }

      final data = await query.order('created_at', ascending: false).limit(20);
      var media = data.map((json) => ForumMedia.fromMap(json)).toList();

      if (media.isNotEmpty) {
        final urls = media.map((m) => m.url).toList();
        final signedMap = await batchSignStorageUrls(urls, 'forum_media');
        media = media.map((m) {
          final path = getPathFromStorageUrl(m.url, 'forum_media');
          final signed = signedMap[path];
          if (signed != null) {
            return m.copyWith(url: signed, thumbnailUrl: signed);
          }
          return m;
        }).toList();
      }

      if (!isClosed) {
        emit(state.copyWith(mediaItems: _sortMedia(media), isLoading: false));
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
          .schema('api').from('v1_forum_media')
          .select()
          .eq('forum_id', forumId);

      if (!isModeratorOrOrganizer) {
        query = query.eq('is_approved', true);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(startIndex, startIndex + 20);

      var more = data.map((json) => ForumMedia.fromMap(json)).toList();

      if (more.isNotEmpty) {
        final urls = more.map((m) => m.url).toList();
        final signedMap = await batchSignStorageUrls(urls, 'forum_media');
        more = more.map((m) {
          final path = getPathFromStorageUrl(m.url, 'forum_media');
          final signed = signedMap[path];
          if (signed != null) {
            return m.copyWith(url: signed, thumbnailUrl: signed);
          }
          return m;
        }).toList();
      }

      if (!isClosed) {
        emit(state.copyWith(
          mediaItems: _sortMedia([...state.mediaItems, ...more]),
          isLoading: false,
        ));
      }
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] Error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(isLoading: false));
    }
  }

  static const _videoExtensions = {
    'mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi', '3gp',
  };

  /// Uploads multiple media items to Cloudflare R2 via Edge Function presigned URL.
  /// Each file's type is inferred from its own extension rather than shared
  /// across the whole batch, so a single call can carry a mix of photos and
  /// videos (e.g. from the unified "Upload Media" picker).
  Future<void> uploadMultipleMedia({
    required List<XFile> files,
  }) async {
    if (isClosed || files.isEmpty) return;
    emit(state.copyWith(isUploading: true));
    try {
      for (final file in files) {
        final bytes = await file.readAsBytes();
        final ext = file.name.split('.').last.toLowerCase();
        final type = _videoExtensions.contains(ext) ? 'video' : 'image';
        final fileId = _uuid.v4();
        final fileName = '$fileId.$ext';
        final mimeType = type == 'video' ? 'video/$ext' : 'image/$ext';

        // 1. Request presigned upload URL from Edge Function
        final uploadResponse = await Supabase.instance.client.functions.invoke(
          'media-signer',
          body: {
            'action': 'upload',
            'folder': 'forum_media/$forumId',
            'filename': fileName,
            'contentType': mimeType,
            'mediaType': type,
          },
        );

        if (uploadResponse.status != 200) {
          throw Exception('Failed to get presigned upload URL');
        }

        final uploadData = uploadResponse.data;
        final uploadUrl = uploadData['uploadUrl'] as String;
        final fileKey = uploadData['fileKey'] as String;

        // 2. Upload file directly to R2
        final putResponse = await http.put(
          Uri.parse(uploadUrl),
          headers: {'Content-Type': mimeType},
          body: bytes,
        );

        if (putResponse.statusCode != 200) {
          throw Exception('Failed to upload file to R2: ${putResponse.body}');
        }

        // 3. Insert record with R2 fileKey (which is signed on-the-fly when read)
        await Supabase.instance.client.schema('social').from('forum_media').insert({
          'id': fileId,
          'forum_id': forumId,
          'uploader_id': userId,
          'media_type': type,
          'media_url': {
            'full_res': fileKey,
            'thumbnail': fileKey,
          },
          'metadata': {
            'mime_type': mimeType,
            'file_size': bytes.length,
          },
          'is_approved': isModeratorOrOrganizer,
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

  /// `forum_media.forum_media` is partitioned by `created_at` with composite
  /// PK (id, created_at), so the row's `createdAt` must be in the WHERE clause
  /// or the UPDATE/DELETE matches no rows.
  Future<void> approveMedia(ForumMedia media) async {
    if (!isModeratorOrOrganizer) return;
    try {
      await Supabase.instance.client
          .schema('social').from('forum_media')
          .update({'is_approved': true})
          .eq('id', media.id)
          .eq('created_at', media.createdAt.toIso8601String());
      await refreshMedia();
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] Error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> deleteMedia(ForumMedia media) async {
    final isUploader = media.uploaderId == userId;
    if (!isModeratorOrOrganizer && !isUploader) return;
    try {
      await Supabase.instance.client
          .schema('social').from('forum_media')
          .delete()
          .eq('id', media.id)
          .eq('created_at', media.createdAt.toIso8601String());
      await refreshMedia();
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] Error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> reportMedia(ForumMedia media, String reason) async {
    try {
      await repo.submitReport(
        targetMediaId: media.id,
        targetMediaCreatedAt: media.createdAt.toIso8601String(),
        reasonId: 'general_abuse',
        description: reason,
      );
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] reportMedia error: $e\n$stack');
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

  @override
  Future<void> close() {
    _mediaSubscription?.unsubscribe();
    return super.close();
  }
}
