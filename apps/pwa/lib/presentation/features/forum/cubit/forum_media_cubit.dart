import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/core/utils/image_resizer.dart';
import 'package:lynk_x/core/utils/retry.dart';
import 'package:lynk_x/core/utils/upload_put.dart';
import 'package:lynk_x/core/utils/storage_utils.dart';
import 'package:lynk_x/data/repositories/forum_repository.dart';
import 'package:lynk_x/presentation/features/forum/core/upload_preview_math.dart';
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

  // Files whose last upload attempt failed, kept so the user can retry without re-picking them.
  List<XFile> _failedFiles = const [];
  bool _failedKeepOriginal = false;
  bool get hasFailedUploads => _failedFiles.isNotEmpty;

  /// Re-attempts every file that failed in the last upload. Files that already uploaded are not
  /// repeated, since only the failures were kept.
  Future<void> retryFailedUploads() async {
    if (_failedFiles.isEmpty) return;
    await uploadMultipleMedia(files: List.of(_failedFiles), keepOriginal: _failedKeepOriginal);
  }

  DateTime? forumCreatedAt;

  bool get isModeratorOrOrganizer => isOrganizer || isModerator;

  /// Storage keys that need signing for [items]: the full-res key, plus the thumbnail
  /// when it's a separate object (legacy rows point both at the same file).
  List<String> _keysToSign(Iterable<ForumMedia> items) => [
        for (final m in items) ...[
          m.url,
          if (m.thumbnailUrl != null && m.thumbnailUrl != m.url) m.thumbnailUrl!,
        ],
      ];

  /// [item] with signed full and thumbnail URLs, or null when the full-res key couldn't
  /// be signed. A thumbnail that fails to sign falls back to the full image.
  ForumMedia? _applySigned(ForumMedia item, Map<String, String> signedMap) {
    final full = signedMap[getPathFromStorageUrl(item.url, 'forum_media')];
    if (full == null) return null;
    final thumbKey = item.thumbnailUrl;
    final thumb = (thumbKey == null || thumbKey == item.url)
        ? full
        : signedMap[getPathFromStorageUrl(thumbKey, 'forum_media')] ?? full;
    return item.copyWith(url: full, thumbnailUrl: thumb);
  }

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
        final signedMap = await batchSignStorageUrls(_keysToSign([mediaItem]), 'forum_media');
        final finalItem = _applySigned(mediaItem, signedMap);

        // Only add if URL was successfully signed into an HTTP URL; otherwise refreshMedia will resolve
        if (finalItem == null) {
          await refreshMedia();
          return;
        }

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
            final signedMap = await batchSignStorageUrls(_keysToSign([mediaItem]), 'forum_media');
            final finalItem = _applySigned(mediaItem, signedMap);
            if (finalItem != null) {
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
        final signedMap = await batchSignStorageUrls(_keysToSign(media), 'forum_media');
        media = media.map((m) => _applySigned(m, signedMap) ?? m).toList();
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
        final signedMap = await batchSignStorageUrls(_keysToSign(more), 'forum_media');
        more = more.map((m) => _applySigned(m, signedMap) ?? m).toList();
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

  // Full images are capped at 2048 px on the long edge; grid thumbnails at 480 px.
  static const _fullMaxEdge = 2048;
  static const _thumbMaxEdge = 480;

  /// Requests a presigned upload URL for [fileName] and PUTs [bytes] to R2.
  /// Returns the stored file key; throws on any failure.
  Future<String> _putToR2(
    Uint8List bytes,
    String fileName,
    String mimeType,
    String mediaType, {
    void Function(double fraction)? onProgress,
  }) {
    // Each attempt asks for a fresh presigned URL, so an expired or half-used one never poisons a retry.
    return retryTransient(() async {
      final uploadResponse = await Supabase.instance.client.functions
          .invoke(
            'media-signer',
            body: {
              'action': 'upload',
              'folder': 'forum_media/$forumId',
              'filename': fileName,
              'contentType': mimeType,
              'mediaType': mediaType,
            },
          )
          .timeout(const Duration(seconds: 30));

      if (uploadResponse.status != 200) {
        throw Exception('Failed to get presigned upload URL: ${uploadResponse.status}');
      }

      final uploadData = uploadResponse.data;
      final uploadUrl = uploadData['uploadUrl'] as String;
      final fileKey = uploadData['fileKey'] as String;

      // Stall-based timeout, not a fixed one: a large video on a slow connection can legitimately
      // take minutes, so this only gives up when no bytes have left the device for 30 s.
      final status = await putBytesWithProgress(
        Uri.parse(uploadUrl),
        bytes,
        mimeType,
        onProgress: onProgress,
      );

      // Accept all 2xx codes (e.g. 200 OK, 204 No Content from S3/R2)
      if (status < 200 || status >= 300) {
        final detail = 'Failed to upload file to R2: HTTP $status';
        // 5xx / 429 are worth another try; other statuses (403 bad signature, 400) are not.
        if (status >= 500 || status == 429) {
          throw TransientFailure(detail);
        }
        throw Exception(detail);
      }
      return fileKey;
    });
  }

  /// Registers the uploaded file via api.add_forum_media, retrying dropped connections. The RPC
  /// checks permissions, resolves forum_created_at and decides approval server-side, and is
  /// idempotent on [id] — so a retry after a lost response returns the existing row rather than
  /// creating a duplicate.
  Future<void> _registerMedia({
    required String id,
    required String mediaType,
    required Map<String, dynamic> mediaUrl,
    required Map<String, dynamic> metadata,
  }) {
    return retryTransient(() async {
      await Supabase.instance.client.schema('api').rpc('add_forum_media', params: {
        'p_forum_id': forumId,
        'p_id': id,
        'p_media_type': mediaType,
        'p_media_url': mediaUrl,
        'p_metadata': metadata,
      });
    });
  }


  /// Uploads multiple media items to Cloudflare R2 via Edge Function presigned URL.
  /// [keepOriginal] uploads photos untouched (organizers, moderators, premium users — decided by
  /// the caller); otherwise photos are downscaled and re-encoded to save data. The grid
  /// thumbnail is generated either way.
  /// Each file's type is inferred from its own extension rather than shared
  /// across the whole batch, so a single call can carry a mix of photos and
  /// videos (e.g. from the unified "Upload Media" picker).
  Future<void> uploadMultipleMedia({
    required List<XFile> files,
    bool keepOriginal = false,
  }) async {
    if (isClosed || files.isEmpty) return;
    emit(state.copyWith(
      isUploading: true,
      uploadCurrent: 0,
      uploadTotal: files.length,
      uploadProgress: 0.0,
      clearError: true,
    ));

    final succeeded = <String>[];
    final errors = <String>[];
    final failedFiles = <XFile>[];
    const maxFileSizeBytes = 100 * 1024 * 1024; // 100 MB max guard

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      if (!isClosed) {
        emit(state.copyWith(
          isUploading: true,
          uploadCurrent: i + 1,
          uploadTotal: files.length,
          uploadProgress: 0.0,
        ));
      }

      try {
        final fileLength = await file.length();
        if (fileLength > maxFileSizeBytes) {
          throw Exception('File "${file.name}" exceeds the 100MB limit');
        }

        var bytes = await file.readAsBytes();
        final ext = file.name.split('.').last.toLowerCase();
        final type = kUploadVideoExtensions.contains(ext) ? 'video' : 'image';
        final fileId = _uuid.v4();
        var fileName = '$fileId.$ext';
        // Normalize MIME type (e.g. image/jpeg instead of non-standard image/jpg)
        // to prevent SigV4 SignatureDoesNotMatch errors.
        var mimeType = (ext == 'jpg' || ext == 'jpeg')
            ? 'image/jpeg'
            : (type == 'video' ? 'video/$ext' : 'image/$ext');

        // Phone photos are routinely 4-8 MB: downscale the full image (unless keepOriginal) and
        // make a small thumbnail for the grid. Skipped for video, and for GIF/SVG (animation / vector),
        // and silently falls back to the untouched original if the browser can't decode it.
        Uint8List? thumbBytes;
        if (type == 'image' && !kUploadKeepAsIsExtensions.contains(ext)) {
          if (!keepOriginal) {
            final resized = await resizeImageToJpeg(bytes, maxEdge: _fullMaxEdge, quality: 0.85);
            if (resized != null && resized.length < bytes.length) {
              bytes = resized;
              fileName = '$fileId.jpg';
              mimeType = 'image/jpeg';
            }
          }
          thumbBytes = await resizeImageToJpeg(bytes, maxEdge: _thumbMaxEdge, quality: 0.75);
        } else if (type == 'video') {
          // A still frame for the grid. Prefer the picker's blob: URL so the video isn't copied;
          // null (undecodable codec, e.g. HEVC outside Safari) just means no thumbnail.
          thumbBytes = await extractVideoPoster(
            url: file.path.startsWith('blob:') ? file.path : null,
            bytes: file.path.startsWith('blob:') ? null : bytes,
            maxEdge: _thumbMaxEdge,
          );
        }

        // 1-2. Presigned URL from the Edge Function, then PUT straight to R2.
        if (!isClosed) emit(state.copyWith(uploadProgress: 0.0));
        final fileKey = await _putToR2(
          bytes,
          fileName,
          mimeType,
          type,
          // Throttled to whole percents so a large upload doesn't rebuild the UI per event.
          onProgress: (fraction) {
            final percent = (fraction * 100).floor() / 100;
            if (!isClosed && percent != state.uploadProgress) {
              emit(state.copyWith(uploadProgress: percent));
            }
          },
        );

        // The thumbnail is best-effort: if it fails the grid just falls back to the full image.
        var thumbKey = fileKey;
        if (thumbBytes != null) {
          try {
            thumbKey = await _putToR2(thumbBytes, '${fileId}_thumb.jpg', 'image/jpeg', 'image');
          } catch (e) {
            debugPrint('[ForumMediaCubit] Thumbnail upload failed for ${file.name}, using full image: $e');
          }
        }

        // 3. Register the media (R2 keys are signed on-the-fly when read)
        await _registerMedia(
          id: fileId,
          mediaType: type,
          mediaUrl: {'full_res': fileKey, 'thumbnail': thumbKey},
          metadata: {
            'mime_type': mimeType,
            'file_size': bytes.length,
            // Lets marketing exports tell untouched originals from downscaled copies.
            if (type == 'image') 'quality': keepOriginal ? 'original' : 'optimized',
          },
        );

        succeeded.add(file.name);
      } catch (e, stack) {
        debugPrint('[ForumMediaCubit] Upload failed for ${file.name}: $e\n$stack');
        errors.add('${file.name}: $e');
        failedFiles.add(file);
      }
    }

    _failedFiles = failedFiles;
    _failedKeepOriginal = keepOriginal;

    if (!isClosed) {
      emit(state.copyWith(
        isUploading: false,
        uploadCurrent: 0,
        uploadTotal: 0,
        uploadProgress: 0.0,
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
