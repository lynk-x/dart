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

/// Owns the forum's media tab — upload (via R2 presigned URLs), moderation
/// (approve/delete), and realtime sync of the media grid.
class ForumMediaCubit extends HydratedCubit<ForumMediaState> {
  static const _uuid = Uuid();
  final String forumId;
  final String userId;
  final bool isOrganizer;
  final bool isModerator;
  final ForumRepository repo;
  RealtimeChannel? _mediaSubscription;

  DateTime? forumCreatedAt;

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
    this.forumCreatedAt,
    required this.userId,
    required this.isOrganizer,
    required this.isModerator,
    required this.repo,
  }) : super(const ForumMediaState());

  /// Synchronizes forum context timestamps for composite foreign keys and partition pruning.
  void syncForumContext({DateTime? forumCreatedAt}) {
    if (forumCreatedAt != null) {
      this.forumCreatedAt = forumCreatedAt;
    }
  }

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

        // Filter permissions: General users only see approved media or their own uploads
        final isOwnUpload = mediaItem.uploaderId == userId;
        if (!isModeratorOrOrganizer && !mediaItem.isApproved && !isOwnUpload) return;

        // Sign URL on-the-fly
        final path = getPathFromStorageUrl(mediaItem.url, 'forum_media');
        final signedMap =
            await batchSignStorageUrls([mediaItem.url], 'forum_media');
        final signed = signedMap[path];

        // Only add if URL was successfully signed into an HTTP URL; otherwise refreshMedia will resolve
        if (signed == null) {
          await refreshMedia();
          return;
        }

        final finalItem = mediaItem.copyWith(url: signed, thumbnailUrl: signed);

        if (!isClosed) {
          final updatedItems = [finalItem, ...state.mediaItems.where((m) => m.id != finalItem.id)];
          emit(state.copyWith(mediaItems: _sortMedia(updatedItems)));
        }
      } else if (payload.eventType == PostgresChangeEvent.update) {
        final data = payload.newRecord;
        final mediaItem = ForumMedia.fromMap(data);
        final isOwnUpload = mediaItem.uploaderId == userId;

        if (!isModeratorOrOrganizer && !mediaItem.isApproved && !isOwnUpload) {
          // If it got unapproved/rejected, remove it for general users (unless own upload)
          final updated =
              state.mediaItems.where((m) => m.id != mediaItem.id).toList();
          if (!isClosed) emit(state.copyWith(mediaItems: _sortMedia(updated)));
        } else {
          // Update approval status or metadata in-place
          final index =
              state.mediaItems.indexWhere((m) => m.id == mediaItem.id);
          if (index != -1) {
            final updatedList = List<ForumMedia>.from(state.mediaItems);
            final existing = updatedList[index];
            // Preserve already signed URLs if urls haven't changed path
            updatedList[index] = mediaItem.copyWith(
              url: existing.url,
              thumbnailUrl: existing.thumbnailUrl,
            );
            if (!isClosed) {
              emit(state.copyWith(mediaItems: _sortMedia(updatedList)));
            }
          } else if (mediaItem.isApproved || isModeratorOrOrganizer || isOwnUpload) {
            // If newly approved/visible, fetch signed URL and prepend
            final path = getPathFromStorageUrl(mediaItem.url, 'forum_media');
            final signedMap =
                await batchSignStorageUrls([mediaItem.url], 'forum_media');
            final signed = signedMap[path];
            if (signed != null) {
              final finalItem =
                  mediaItem.copyWith(url: signed, thumbnailUrl: signed);

              if (!isClosed) {
                final updatedItems = [
                  finalItem,
                  ...state.mediaItems.where((m) => m.id != finalItem.id),
                ];
                emit(state.copyWith(mediaItems: _sortMedia(updatedItems)));
              }
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
          .schema('api')
          .from('v1_forum_media')
          .select()
          .eq('forum_id', forumId);

      if (!isModeratorOrOrganizer) {
        query = query.or('is_approved.eq.true,uploader_id.eq.$userId');
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
        emit(state.copyWith(
          mediaItems: _sortMedia(media),
          isLoading: false,
          hasMore: data.length >= 20,
        ));
      }
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] Error: $e\n$stack');
      if (!isClosed) {
        emit(state.copyWith(isLoading: false, error: e.toString()));
      }
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isUploading || !state.hasMore || isClosed) return;
    emit(state.copyWith(isLoading: true));
    final startIndex = state.mediaItems.length;
    const pageSize = 20;
    try {
      var query = Supabase.instance.client
          .schema('api')
          .from('v1_forum_media')
          .select()
          .eq('forum_id', forumId);

      if (!isModeratorOrOrganizer) {
        query = query.or('is_approved.eq.true,uploader_id.eq.$userId');
      }

      // Supabase range is inclusive on both ends: [startIndex, startIndex + pageSize - 1]
      final data = await query
          .order('created_at', ascending: false)
          .range(startIndex, startIndex + pageSize - 1);

      if (data.isEmpty) {
        if (!isClosed) {
          emit(state.copyWith(isLoading: false, hasMore: false));
        }
        return;
      }

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
        // Prevent duplicate keys by filtering against already loaded IDs
        final existingIds = state.mediaItems.map((m) => m.id).toSet();
        final uniqueMore = more.where((m) => !existingIds.contains(m.id)).toList();
        emit(state.copyWith(
          mediaItems: _sortMedia([...state.mediaItems, ...uniqueMore]),
          isLoading: false,
          hasMore: data.length >= pageSize,
        ));
      }
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] Error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(isLoading: false));
    }
  }

  static const _videoExtensions = {
    'mp4',
    'mov',
    'm4v',
    'webm',
    'mkv',
    'avi',
    '3gp',
  };

  /// Uploads multiple media items to Cloudflare R2 via Edge Function presigned URL.
  /// Each file's type is inferred from its own extension rather than shared
  /// across the whole batch, so a single call can carry a mix of photos and
  /// videos (e.g. from the unified "Upload Media" picker).
  Future<void> uploadMultipleMedia({
    required List<XFile> files,
  }) async {
    if (isClosed || files.isEmpty) return;
    emit(state.copyWith(
      isUploading: true,
      uploadCurrent: 0,
      uploadTotal: files.length,
      clearError: true,
    ));

    final succeeded = <String>[];
    final errors = <String>[];
    const maxFileSizeBytes = 100 * 1024 * 1024; // 100 MB max guard

    // Resolve forumCreatedAt for the composite foreign key (forum_id, forum_created_at)
    // and RLS policy partition pruning.
    DateTime? effectiveForumCreatedAt = forumCreatedAt;
    if (effectiveForumCreatedAt == null) {
      try {
        final res = await Supabase.instance.client
            .schema('social')
            .from('forums')
            .select('created_at')
            .eq('id', forumId)
            .maybeSingle();
        if (res != null && res['created_at'] != null) {
          effectiveForumCreatedAt = DateTime.parse(res['created_at'] as String);
          forumCreatedAt = effectiveForumCreatedAt;
        }
      } catch (e) {
        debugPrint('[ForumMediaCubit] Fallback forumCreatedAt fetch failed: $e');
      }
    }

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      if (!isClosed) {
        emit(state.copyWith(
          isUploading: true,
          uploadCurrent: i + 1,
          uploadTotal: files.length,
        ));
      }

      try {
        final fileLength = await file.length();
        if (fileLength > maxFileSizeBytes) {
          throw Exception('File "${file.name}" exceeds the 100MB limit');
        }

        final bytes = await file.readAsBytes();
        final ext = file.name.split('.').last.toLowerCase();
        final type = _videoExtensions.contains(ext) ? 'video' : 'image';
        final fileId = _uuid.v4();
        final fileName = '$fileId.$ext';
        // Normalize MIME type (e.g. image/jpeg instead of non-standard image/jpg)
        // to prevent SigV4 SignatureDoesNotMatch errors.
        final mimeType = (ext == 'jpg' || ext == 'jpeg')
            ? 'image/jpeg'
            : (type == 'video' ? 'video/$ext' : 'image/$ext');

        // 1. Request presigned upload URL from Edge Function with timeout
        final uploadResponse = await Supabase.instance.client.functions
            .invoke(
              'media-signer',
              body: {
                'action': 'upload',
                'folder': 'forum_media/$forumId',
                'filename': fileName,
                'contentType': mimeType,
                'mediaType': type,
              },
            )
            .timeout(const Duration(seconds: 30));

        if (uploadResponse.status != 200) {
          throw Exception('Failed to get presigned upload URL: ${uploadResponse.status}');
        }

        final uploadData = uploadResponse.data;
        final uploadUrl = uploadData['uploadUrl'] as String;
        final fileKey = uploadData['fileKey'] as String;

        // 2. Upload file directly to R2 with timeout
        final putResponse = await http
            .put(
              Uri.parse(uploadUrl),
              headers: {'Content-Type': mimeType},
              body: bytes,
            )
            .timeout(const Duration(seconds: 60));

        // Accept all 2xx codes (e.g. 200 OK, 204 No Content from S3/R2)
        if (putResponse.statusCode < 200 || putResponse.statusCode >= 300) {
          throw Exception(
              'Failed to upload file to R2: HTTP ${putResponse.statusCode} - ${putResponse.body}');
        }

        // 3. Insert record with R2 fileKey (which is signed on-the-fly when read)
        await Supabase.instance.client
            .schema('social')
            .from('forum_media')
            .insert({
          'id': fileId,
          'forum_id': forumId,
          if (effectiveForumCreatedAt != null)
            'forum_created_at': effectiveForumCreatedAt.toUtc().toIso8601String(),
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

        succeeded.add(file.name);
      } catch (e, stack) {
        debugPrint('[ForumMediaCubit] Upload failed for ${file.name}: $e\n$stack');
        errors.add('${file.name}: $e');
      }
    }

    if (!isClosed) {
      emit(state.copyWith(
        isUploading: false,
        uploadCurrent: 0,
        uploadTotal: 0,
        error: errors.isNotEmpty
            ? (succeeded.isEmpty
                ? 'Upload failed: ${errors.join(', ')}'
                : 'Uploaded ${succeeded.length}/${files.length} items. Failed: ${errors.join(', ')}')
            : null,
      ));
      if (succeeded.isNotEmpty) {
        await refreshMedia();
      }
    }

    if (errors.isNotEmpty) {
      throw Exception(errors.join('\n'));
    }
  }

  /// `forum_media.forum_media` is partitioned by `created_at` with composite
  /// PK (id, created_at), so the row's `createdAt` must be in the WHERE clause
  /// or the UPDATE/DELETE matches no rows. Returns `true` on success, `false`
  /// on permission denial or failure. isModeratorOrOrganizer is only a UI
  /// fast path — the actual gate is
  /// social.fn_guard_forum_media_approval's is_forum_media_moderator()
  /// check, which also grants privilege via system-admin status or an
  /// account-level can_manage_forum permission this flag can't see.
  Future<bool> approveMedia(ForumMedia media) async {
    try {
      await Supabase.instance.client
          .schema('social')
          .from('forum_media')
          .update({'is_approved': true})
          .eq('id', media.id)
          .eq('created_at', media.createdAt.toIso8601String());
      await refreshMedia();
      return true;
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] Error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(error: e.toString()));
      return false;
    }
  }

  /// Returns `true` on success, `false` on permission denial or failure.
  /// The "ForumMedia: delete" RLS policy already allows the uploader, a
  /// moderator/organizer, an account-level can_manage_forum holder, or a
  /// system admin — the same broader set as approveMedia's guard, so no
  /// client-side gate duplicates it here.
  Future<bool> deleteMedia(ForumMedia media) async {
    try {
      await Supabase.instance.client
          .schema('social')
          .from('forum_media')
          .delete()
          .eq('id', media.id)
          .eq('created_at', media.createdAt.toIso8601String());
      await refreshMedia();
      return true;
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] Error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(error: e.toString()));
      return false;
    }
  }

  /// [reasonId] must match a row in reports.report_reasons (e.g. 'spam',
  /// 'harassment', 'inappropriate', 'likeness_no_consent') or the insert
  /// fails its foreign key constraint.
  Future<void> reportMedia(ForumMedia media, String reasonId) async {
    try {
      await repo.submitReport(
        targetMediaId: media.id,
        targetMediaCreatedAt: media.createdAt.toIso8601String(),
        reasonId: reasonId,
        description: 'Reported from media viewer',
      );
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] reportMedia error: $e\n$stack');
      rethrow;
    }
  }

  /// Opts a media item out of event marketing recaps, ads, and promotional materials.
  /// Callable by any forum member (e.g. attendee pictured), the uploader, or an organizer.
  Future<bool> optOutMarketing(ForumMedia media) async {
    try {
      await Supabase.instance.client.schema('api').rpc(
        'opt_out_media_marketing',
        params: {
          'p_media_id': media.id,
          'p_media_created_at': media.createdAt.toIso8601String(),
        },
      );

      final idx = state.mediaItems.indexWhere((m) => m.id == media.id);
      if (idx != -1) {
        final updatedList = List<ForumMedia>.from(state.mediaItems);
        final currentMeta = Map<String, dynamic>.from(media.metadata ?? {});
        currentMeta['is_marketing_eligible'] = false;
        updatedList[idx] = media.copyWith(metadata: currentMeta);
        if (!isClosed) emit(state.copyWith(mediaItems: updatedList));
      }
      return true;
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] optOutMarketing error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(error: e.toString()));
      return false;
    }
  }

  /// Sets whether a media item is eligible for event marketing recaps.
  /// Re-enabling (setting true) is restricted to the uploader or an organizer.
  Future<bool> setMarketingEligibility(ForumMedia media, bool isEligible) async {
    try {
      await Supabase.instance.client.schema('api').rpc(
        'set_media_marketing_eligibility',
        params: {
          'p_media_id': media.id,
          'p_media_created_at': media.createdAt.toIso8601String(),
          'p_is_eligible': isEligible,
        },
      );

      final idx = state.mediaItems.indexWhere((m) => m.id == media.id);
      if (idx != -1) {
        final updatedList = List<ForumMedia>.from(state.mediaItems);
        final currentMeta = Map<String, dynamic>.from(media.metadata ?? {});
        currentMeta['is_marketing_eligible'] = isEligible;
        updatedList[idx] = media.copyWith(metadata: currentMeta);
        if (!isClosed) emit(state.copyWith(mediaItems: updatedList));
      }
      return true;
    } catch (e, stack) {
      debugPrint('[ForumMediaCubit] setMarketingEligibility error: $e\n$stack');
      if (!isClosed) emit(state.copyWith(error: e.toString()));
      return false;
    }
  }

  void clearError() {
    emit(state.copyWith(clearError: true));
  }

  @override
  ForumMediaState? fromJson(Map<String, dynamic> json) =>
      ForumMediaState.fromMap(json);

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
