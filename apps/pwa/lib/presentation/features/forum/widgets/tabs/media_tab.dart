import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_state.dart';
import 'package:lynk_x/presentation/features/forum/widgets/forum_skeletons.dart';
import 'package:lynk_x/presentation/features/forum/widgets/web_camera_capture.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import 'package:lynk_x/presentation/shared/utils/permission_acks.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/core/network/lynk_cache_manager.dart';
import 'package:lynk_x/core/utils/image_optimizer.dart';

/// The 'Media' tab content for the Forum.
class MediaTab extends StatefulWidget {
  final Function(ForumMedia) onMediaTap;

  const MediaTab({
    super.key,
    required this.onMediaTap,
  });

  @override
  State<MediaTab> createState() => _MediaTabState();
}

class _MediaTabState extends State<MediaTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  bool _loadMoreTriggered = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    final nearBottom = pos.pixels >= pos.maxScrollExtent - 200;
    if (nearBottom && !_loadMoreTriggered) {
      _loadMoreTriggered = true;
      context.read<ForumMediaCubit>().loadMore().whenComplete(
            () => _loadMoreTriggered = false,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final mediaCubit = context.read<ForumMediaCubit>();

    return BlocBuilder<ForumCubit, ForumState>(
      buildWhen: (p, c) =>
          p.isMuted != c.isMuted || p.isReadOnly != c.isReadOnly,
      builder: (context, mainState) {
        return BlocBuilder<ForumMediaCubit, ForumMediaState>(
          builder: (context, mediaState) {
            return Column(
              children: [
                Expanded(
                  child: RepaintBoundary(
                    child: RefreshIndicator(
                      onRefresh: () async => mediaCubit.refreshMedia(),
                      color: context.accentColor,
                      child: SkeletonFadeSingleMount(
                        child: mediaState.isLoading &&
                                mediaState.mediaItems.isEmpty
                            ? const SkeletonMediaGrid(key: ValueKey('skeleton'))
                            : mediaState.mediaItems.isEmpty
                                ? const EmptyState(
                                    key: ValueKey('empty'),
                                    message:
                                        'No media uploaded yet.\nShare your first photo or video!')
                                : CustomScrollView(
                                    key: const ValueKey('content'),
                                    controller: _scrollController,
                                  slivers: [
                                    SliverOverlapInjector(
                                      handle: NestedScrollView
                                          .sliverOverlapAbsorberHandleFor(
                                              context),
                                    ),
                                    SliverPadding(
                                      padding: const EdgeInsets.all(16),
                                      sliver: SliverGrid(
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: MediaQuery.of(context)
                                                      .size
                                                      .width <
                                                  600
                                              ? 3
                                              : 4,
                                          mainAxisSpacing: 8,
                                          crossAxisSpacing: 8,
                                          childAspectRatio: 1.3,
                                        ),
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) {
                                            if (index ==
                                                mediaState.mediaItems.length) {
                                              return Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: context.accentColor));
                                            }
                                            final item =
                                                mediaState.mediaItems[index];
                                            final isVideo =
                                                item.mediaType == 'video';
                                            final displayUrl =
                                                item.thumbnailUrl ?? item.url;

                                            return RepaintBoundary(
                                              child: GestureDetector(
                                                onTap: () =>
                                                    widget.onMediaTap(item),
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      child: isVideo
                                                          ? const _VideoThumbnailPreview()
                                                          : CachedNetworkImage(
                                                              imageUrl: ImageOptimizer.getOptimizedUrl(
                                                                displayUrl,
                                                                width: 300,
                                                              ),
                                                              cacheManager:
                                                                  LynkCacheManager
                                                                      .instance,
                                                              fit: BoxFit.cover,
                                                              memCacheWidth:
                                                                  300,
                                                              placeholder:
                                                                  (context,
                                                                          url) =>
                                                                      Container(
                                                                color: Colors
                                                                    .grey[900],
                                                                child:
                                                                    const Center(
                                                                  child:
                                                                      SizedBox(
                                                                    width: 16,
                                                                    height: 16,
                                                                    child:
                                                                        CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          1.5,
                                                                      color: AppColors
                                                                          .tertiary,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              errorWidget:
                                                                  (context, url,
                                                                          error) =>
                                                                      Container(
                                                                color: Colors
                                                                    .grey[900],
                                                                child: const Icon(
                                                                    Icons
                                                                        .broken_image,
                                                                    color: Colors
                                                                        .white10),
                                                              ),
                                                            ),
                                                    ),
                                                    if (!item.isApproved)
                                                      Container(
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.black54,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                        child: const Center(
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Icon(
                                                                  Icons
                                                                      .pending_actions,
                                                                  color: Colors
                                                                      .white,
                                                                  size: 24),
                                                              SizedBox(
                                                                  height: 4),
                                                              Text('Pending',
                                                                  style: TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontSize:
                                                                          10,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold)),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                          childCount: mediaState
                                                  .mediaItems.length +
                                              (mediaState.isLoading ? 1 : 0),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                      ),
                    ),
                  ),
                ),
                if (!mainState.isMuted &&
                    (!mainState.isReadOnly || mainState.isOrganizer))
                  _buildUploadActions(context, mediaState.isUploading),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildUploadActions(BuildContext context, bool isUploading) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: PrimaryButton(
              icon: isUploading ? null : Icons.photo_camera,
              text: isUploading ? 'Uploading...' : 'Open Camera',
              onPressed: isUploading ? null : () => _openCamera(context),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PrimaryButton(
              icon: isUploading ? null : Icons.photo_library,
              text: isUploading ? 'Uploading...' : 'Upload Media',
              onPressed: isUploading ? null : () => _pickFromGallery(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCamera(BuildContext context) async {
    await PermissionAcks.ensureAcknowledged(
      context,
      PermissionAckType.camera,
      title: 'Use your Camera',
      description:
          'To capture photos and videos for the forum, we need access to your device camera.',
      icon: Icons.camera_alt_rounded,
      actionLabel: 'Enable Camera',
      onReady: () {
        if (context.mounted) _actuallyOpenCamera(context);
      },
    );
  }

  Future<void> _actuallyOpenCamera(BuildContext context) async {
    final mediaCubit = context.read<ForumMediaCubit>();
    final result = await Navigator.of(context).push<WebCameraCaptureResult>(
      MaterialPageRoute(builder: (_) => const WebCameraCaptureScreen()),
    );
    if (result == null || !context.mounted) return;

    if (result.openGallery) {
      await _pickFromGallery(context);
      return;
    }

    final ext = result.isVideo ? 'webm' : 'jpg';
    final file = XFile(
      result.objectUrl,
      name: '${mediaCubit.forumId}-${DateTime.now().millisecondsSinceEpoch}.$ext',
      mimeType: result.isVideo ? 'video/webm' : 'image/jpeg',
    );

    try {
      await _upload(context, mediaCubit, [file]);
    } finally {
      // uploadMultipleMedia has read the blob's bytes by now (success or
      // failure) — release it from browser memory rather than leaking it
      // until the page reloads.
      revokeWebCameraCaptureUrl(result.objectUrl);
    }
  }

  Future<void> _pickFromGallery(BuildContext context) async {
    await PermissionAcks.ensureAcknowledged(
      context,
      PermissionAckType.media,
      title: 'Access your Media',
      description:
          'To share photos and videos with the forum, we need access to your device library.',
      icon: Icons.perm_media_rounded,
      actionLabel: 'Allow Access',
      onReady: () {
        if (context.mounted) _actuallyPickFromGallery(context);
      },
    );
  }

  Future<void> _actuallyPickFromGallery(BuildContext context) async {
    final mediaCubit = context.read<ForumMediaCubit>();
    try {
      // FileType.media covers images and videos together in one multi-select
      // pass — the button no longer splits by type, so the picker shouldn't
      // either. Each file's actual type is inferred from its extension by
      // uploadMultipleMedia.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      final pickedFiles = <XFile>[
        for (final file in result.files)
          if (file.bytes != null)
            XFile.fromData(file.bytes!, name: file.name, length: file.size),
      ];

      if (pickedFiles.isNotEmpty && context.mounted) {
        await _upload(context, mediaCubit, pickedFiles);
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackBars.showError(
          context,
          'Access denied or upload failed. Please check your device settings.',
        );
      }
    }
  }

  Future<void> _upload(
    BuildContext context,
    ForumMediaCubit mediaCubit,
    List<XFile> files,
  ) async {
    try {
      final count = files.length;
      AppSnackBars.showInfo(
        context,
        'Uploading $count ${count > 1 ? 'items' : 'item'}...',
      );

      await mediaCubit.uploadMultipleMedia(files: files);

      if (context.mounted) {
        AppSnackBars.showSuccess(context,
            'Upload successful! ${count > 1 ? 'Items are' : 'Media is'} being processed.');
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackBars.showError(
          context,
          'Access denied or upload failed. Please check your device settings.',
        );
      }
    }
  }
}

class _VideoThumbnailPreview extends StatelessWidget {
  const _VideoThumbnailPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Icon(Icons.play_circle_fill, color: Colors.white38, size: 36),
      ),
    );
  }
}
