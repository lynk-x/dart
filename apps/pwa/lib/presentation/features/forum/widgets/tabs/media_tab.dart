import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_state.dart';
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
                      child: mediaState.isLoading &&
                              mediaState.mediaItems.isEmpty
                          ? CustomScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                        color: context.accentColor),
                                  ),
                                ),
                              ],
                            )
                          : mediaState.mediaItems.isEmpty
                              ? const EmptyState(
                                  message: 'No media uploaded yet.\nShare your first photo or video!')
                              : CustomScrollView(
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
              icon: isUploading ? null : Icons.image,
              text: isUploading ? 'Uploading...' : 'Upload images',
              onPressed: isUploading
                  ? null
                  : () => _pickAndUpload(context, ImageSource.gallery, false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PrimaryButton(
              icon: isUploading ? null : Icons.video_collection,
              text: isUploading ? 'Uploading...' : 'Upload videos',
              onPressed: isUploading
                  ? null
                  : () => _pickAndUpload(context, ImageSource.gallery, true),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload(
      BuildContext context, ImageSource source, bool isVideo) async {
    await PermissionAcks.ensureAcknowledged(
      context,
      PermissionAckType.media,
      title: 'Access your Media',
      description:
          'To share photos and videos with the forum, we need access to your device library.',
      icon: Icons.perm_media_rounded,
      actionLabel: 'Allow Access',
      onReady: () {
        if (context.mounted) _actuallyPickAndUpload(context, source, isVideo);
      },
    );
  }

  Future<void> _actuallyPickAndUpload(
      BuildContext context, ImageSource source, bool isVideo) async {
    final mediaCubit = context.read<ForumMediaCubit>();
    try {
      final List<XFile> pickedFiles = [];

      if (source == ImageSource.gallery) {
        // FilePicker supports multi-select for both images and videos on PWA/Web
        final result = await FilePicker.platform.pickFiles(
          type: isVideo ? FileType.video : FileType.image,
          allowMultiple: true,
        );

        if (result != null && result.files.isNotEmpty) {
          for (final file in result.files) {
            if (file.bytes != null) {
              pickedFiles.add(XFile.fromData(
                file.bytes!,
                name: file.name,
                length: file.size,
              ));
            }
          }
        }
      } else {
        // Fallback for camera/single pick
        final picker = ImagePicker();
        if (isVideo) {
          final XFile? file = await picker.pickVideo(source: source);
          if (file != null) pickedFiles.add(file);
        } else {
          final XFile? file =
              await picker.pickImage(source: source, imageQuality: 70);
          if (file != null) pickedFiles.add(file);
        }
      }

      if (pickedFiles.isNotEmpty && context.mounted) {
        final count = pickedFiles.length;
        AppSnackBars.showInfo(context,
            'Uploading $count ${isVideo ? (count > 1 ? 'videos' : 'video') : (count > 1 ? 'images' : 'image')}...');

        await mediaCubit.uploadMultipleMedia(
          files: pickedFiles,
          type: isVideo ? 'video' : 'image',
        );

        if (context.mounted) {
          AppSnackBars.showSuccess(context,
              'Upload successful! ${count > 1 ? 'Items are' : 'Media is'} being processed.');
        }
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
