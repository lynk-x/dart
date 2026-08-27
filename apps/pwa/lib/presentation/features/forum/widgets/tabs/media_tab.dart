import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
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
import 'package:lynk_x/presentation/features/forum/widgets/disabled_state_bar.dart';
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
                            // Every branch here needs its own
                            // SliverOverlapInjector, unconditionally —
                            // forum_screen.dart's NestedScrollView header
                            // always has exactly one SliverOverlapAbsorber
                            // expecting exactly one injector per frame, or it
                            // throws (opaque minified exception, blank grey
                            // content area) whenever a branch without one is
                            // the one showing — as happens on every fresh
                            // forum open before the first media page loads.
                            ? CustomScrollView(
                                key: const ValueKey('skeleton'),
                                controller: _scrollController,
                                slivers: [
                                  SliverOverlapInjector(
                                    handle: NestedScrollView
                                        .sliverOverlapAbsorberHandleFor(context),
                                  ),
                                  const SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: SkeletonMediaGrid(),
                                  ),
                                ],
                              )
                            : mediaState.mediaItems.isEmpty
                                ? CustomScrollView(
                                    key: const ValueKey('empty'),
                                    controller: _scrollController,
                                    slivers: [
                                      SliverOverlapInjector(
                                        handle: NestedScrollView
                                            .sliverOverlapAbsorberHandleFor(context),
                                      ),
                                      const SliverFillRemaining(
                                        child: EmptyState(
                                            message:
                                                'No media uploaded yet.\nShare your first photo or video!'),
                                      ),
                                    ],
                                  )
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
                                              key: ValueKey(item.id),
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
                  _buildUploadActions(context, mediaState.isUploading)
                else if (mainState.isMuted)
                  const DisabledStateBar(state: DisabledForumState.muted)
                else if (mainState.isArchived && !mainState.isOrganizer)
                  const DisabledStateBar(state: DisabledForumState.archived)
                else if (mainState.isReadOnly && !mainState.isOrganizer)
                  const DisabledStateBar(state: DisabledForumState.readOnly),
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
    // Routed through go_router (not a raw Navigator.push) so it gets its
    // own browser URL/history entry on web — pushing outside go_router left
    // the browser back button with no matching history state for "camera
    // screen open", so it fell through to whatever page was in history
    // before the forum was ever opened (sometimes the homepage), instead of
    // returning to the Media tab.
    final forumReference = context.read<ForumCubit>().forumReference;
    final result = await context.push<WebCameraCaptureResult>(
      '/forum/$forumReference/camera',
    );
    if (result == null || !context.mounted) return;

    if (result.pickedFiles.isNotEmpty) {
      await _upload(context, mediaCubit, result.pickedFiles);
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
      // image_picker rather than file_picker: file_picker's FileType.media
      // sets accept="video/*|image/*" on the underlying <input type="file">
      // web element — pipe-separated, which isn't valid HTML accept syntax
      // (the spec requires commas). Browsers silently ignore the malformed
      // filter and fall back to a generic file browser instead of the
      // native Photos/Gallery picker. image_picker's getMedia() uses the
      // correct "image/*,video/*". Each file's actual type is inferred from
      // its extension by uploadMultipleMedia.
      final pickedFiles = await ImagePicker().pickMultipleMedia();

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
