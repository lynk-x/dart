import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';

/// The 'Media' tab content for the Forum.
class MediaTab extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final VoidCallback onScrollToBottom;
  final Function(ForumMedia) onMediaTap;
  final List<ForumMedia> mediaItems;
  final bool isLoading;
  final Future<void> Function(XFile, String, String) onUpload;
  final bool isMuted;
  final bool isUploading;

  const MediaTab({
    super.key,
    required this.onRefresh,
    required this.onScrollToBottom,
    required this.onMediaTap,
    required this.mediaItems,
    required this.isLoading,
    required this.onUpload,
    this.isMuted = false,
    this.isUploading = false,
  });

  @override
  State<MediaTab> createState() => _MediaTabState();
}

class _MediaTabState extends State<MediaTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

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
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      widget.onScrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Expanded(
          child: RepaintBoundary(
            child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              color: AppColors.primary,
              child: widget.isLoading && widget.mediaItems.isEmpty
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    )
                  : widget.mediaItems.isEmpty
                      ? const EmptyState(message: 'No media uploaded yet.')
                      : GridView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: widget.mediaItems.length +
                              (widget.isLoading ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == widget.mediaItems.length) {
                              return const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2));
                            }
                            final item = widget.mediaItems[index];
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
                                      child: CachedNetworkImage(
                                        imageUrl: displayUrl,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 300,
                                        placeholder: (context, url) =>
                                            Container(
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
                                        errorWidget: (context, url, error) =>
                                            Container(
                                          color: Colors.grey[900],
                                          child: const Icon(Icons.broken_image,
                                              color: Colors.white10),
                                        ),
                                      ),
                                    ),
                                    if (isVideo)
                                      const Center(
                                        child: Icon(Icons.play_circle_fill,
                                            color: Colors.white70, size: 30),
                                      ),
                                    if (!item.isApproved)
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius:
                                              BorderRadius.circular(8),
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
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ),
        if (!widget.isMuted) _buildUploadActions(context),
      ],
    );
  }

  Widget _buildUploadActions(BuildContext context) {
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
              icon: widget.isUploading ? null : Icons.image,
              text: widget.isUploading ? 'Uploading...' : 'Upload image',
              onPressed: widget.isUploading
                  ? null
                  : () => _pickAndUpload(context, ImageSource.gallery, false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PrimaryButton(
              icon: widget.isUploading ? null : Icons.video_collection,
              text: widget.isUploading ? 'Uploading...' : 'Upload video',
              onPressed: widget.isUploading
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
    try {
      final picker = ImagePicker();
      final XFile? pickedFile = isVideo
          ? await picker.pickVideo(source: source)
          : await picker.pickImage(source: source, imageQuality: 70);

      if (pickedFile != null) {
        final ext = pickedFile.path.split('.').last.toLowerCase();
        final mimeType = isVideo ? 'video/$ext' : 'image/$ext';

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uploading ${isVideo ? 'video' : 'image'}...'),
            duration: const Duration(seconds: 1),
          ),
        );

        await widget.onUpload(
            pickedFile, isVideo ? 'video' : 'image', mimeType);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload successfully!')),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload media')),
        );
      }
    }
  }
}
