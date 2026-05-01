import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_state.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/core/network/lynk_cache_manager.dart';


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
      buildWhen: (p, c) => p.isMuted != c.isMuted || p.isReadOnly != c.isReadOnly,
      builder: (context, mainState) {
        return BlocBuilder<ForumMediaCubit, ForumMediaState>(
          builder: (context, mediaState) {
            return Column(
              children: [
                Expanded(
                  child: RepaintBoundary(
                    child: RefreshIndicator(
                      onRefresh: () async => mediaCubit.refreshMedia(),
                      color: AppColors.primary,
                      child: mediaState.isLoading && mediaState.mediaItems.isEmpty
                          ? const Center(
                              child: CircularProgressIndicator(color: AppColors.primary),
                            )
                          : mediaState.mediaItems.isEmpty
                              ? const EmptyState(message: 'No media uploaded yet.')
                              : CustomScrollView(
                                  controller: _scrollController,
                                  slivers: [
                                    SliverPadding(
                                      padding: const EdgeInsets.all(16),
                                      sliver: SliverGrid(
                                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 3,
                                          mainAxisSpacing: 8,
                                          crossAxisSpacing: 8,
                                        ),
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) {
                                    if (index == mediaState.mediaItems.length) {
                                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                                    }
                                    final item = mediaState.mediaItems[index];
                                    final isVideo = item.mediaType == 'video';
                                    final displayUrl = item.thumbnailUrl ?? item.url;

                                    return RepaintBoundary(
                                      child: GestureDetector(
                                        onTap: () => widget.onMediaTap(item),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: isVideo
                                                  ? const _VideoThumbnailPreview()
                                                  : CachedNetworkImage(
                                                      imageUrl: displayUrl,
                                                      cacheManager: LynkCacheManager.instance,
                                                      fit: BoxFit.cover,
                                                      memCacheWidth: 300,
                                                      placeholder: (context, url) => Container(
                                                        color: Colors.grey[900],
                                                        child: const Center(
                                                          child: SizedBox(
                                                            width: 16,
                                                            height: 16,
                                                            child: CircularProgressIndicator(
                                                              strokeWidth: 1.5,
                                                              color: AppColors.tertiary,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      errorWidget: (context, url, error) => Container(
                                                        color: Colors.grey[900],
                                                        child: const Icon(Icons.broken_image,
                                                            color: Colors.white10),
                                                      ),
                                                    ),
                                            ),
                                            if (!item.isApproved)
                                              Container(
                                                decoration: BoxDecoration(
                                                  color: Colors.black54,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Center(
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.pending_actions,
                                                          color: Colors.white,
                                                          size: 24),
                                                      SizedBox(height: 4),
                                                      Text('Pending',
                                                          style: TextStyle(
                                                              color: Colors.white,
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.bold)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  childCount: mediaState.mediaItems.length +
                                      (mediaState.isLoading ? 1 : 0),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!mainState.isMuted && (!mainState.isReadOnly || mainState.isOrganizer))
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
              text: isUploading ? 'Uploading...' : 'Upload image',
              onPressed: isUploading ? null : () => _pickAndUpload(context, ImageSource.gallery, false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PrimaryButton(
              icon: isUploading ? null : Icons.video_collection,
              text: isUploading ? 'Uploading...' : 'Upload video',
              onPressed: isUploading ? null : () => _pickAndUpload(context, ImageSource.gallery, true),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload(BuildContext context, ImageSource source, bool isVideo) async {
    final mediaCubit = context.read<ForumMediaCubit>();
    try {
      final picker = ImagePicker();
      final XFile? pickedFile = isVideo
          ? await picker.pickVideo(source: source)
          : await picker.pickImage(source: source, imageQuality: 70);

      if (pickedFile != null && context.mounted) {
        final ext = pickedFile.path.split('.').last.toLowerCase();
        final mimeType = isVideo ? 'video/$ext' : 'image/$ext';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uploading ${isVideo ? 'video' : 'image'}...'),
            duration: const Duration(seconds: 1),
          ),
        );

        await mediaCubit.uploadMedia(
          file: pickedFile,
          type: isVideo ? 'video' : 'image',
          mimeType: mimeType,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload successful!')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not access ${isVideo ? 'video' : 'image'} library: ${e.toString()}')),
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

