import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_core/core.dart';

/// A full-screen multimedia viewer for high-resolution images and videos.
/// Optimized for PWA with web-native behaviors and smooth transitions.
class MediaViewer extends StatefulWidget {
  final String? imageUrl;
  final ForumMedia? mediaItem;
  final VoidCallback? onMention;
  final VoidCallback? onApprove;

  const MediaViewer({
    super.key,
    this.imageUrl,
    this.mediaItem,
    this.onMention,
    this.onApprove,
  });

  static void show(BuildContext context,
      {String? imageUrl,
      ForumMedia? mediaItem,
      VoidCallback? onMention,
      VoidCallback? onApprove}) {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: MediaViewer(
            imageUrl: imageUrl,
            mediaItem: mediaItem,
            onMention: onMention,
            onApprove: onApprove),
      ),
    );
  }

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  VideoPlayerController? _videoController;
  bool _isVideo = false;

  @override
  void initState() {
    super.initState();
    final url = widget.mediaItem?.url ?? widget.imageUrl;
    _isVideo = widget.mediaItem?.mediaType == 'video' || (url?.contains('.mp4') ?? false);
    
    if (_isVideo && url != null) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url))
        ..initialize().then((_) {
          setState(() {});
          _videoController?.play();
          _videoController?.setLooping(true);
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _downloadMedia() async {
    final targetUrl = widget.mediaItem?.url ?? widget.imageUrl;
    if (targetUrl == null) return;

    final uri = Uri.tryParse(targetUrl);
    if (uri != null) {
      // For PWA/Web, we open in a new tab which allows native browser download/save.
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetUrl = widget.mediaItem?.url ?? widget.imageUrl;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Content Area
          Center(
            child: _isVideo
                ? _buildVideoPlayer()
                : _buildImageViewer(targetUrl),
          ),

          // Top Controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _CircleButton(
                  icon: Icons.close,
                  onPressed: () => Navigator.pop(context),
                ),
                if (widget.mediaItem != null)
                  Text(
                    widget.mediaItem!.mediaType.toUpperCase(),
                    style: AppTypography.inter(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                _CircleButton(
                  icon: Icons.download_rounded,
                  onPressed: _downloadMedia,
                ),
              ],
            ),
          ),

          // Bottom Actions
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 30,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionButton(
                  icon: Icons.alternate_email,
                  label: 'Mention',
                  onTap: () {
                    Navigator.pop(context);
                    widget.onMention?.call();
                  },
                ),
                if (widget.onApprove != null) ...[
                  const SizedBox(width: 40),
                  _ActionButton(
                    icon: Icons.check_circle_outline,
                    label: 'Approve',
                    color: context.accentColor,
                    onTap: () {
                      Navigator.pop(context);
                      widget.onApprove?.call();
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageViewer(String? url) {
    if (url == null) return const Center(child: Icon(Icons.broken_image, color: Colors.white24));

    return PhotoView(
      imageProvider: NetworkImage(url),
      loadingBuilder: (context, event) => Center(
        child: CircularProgressIndicator(color: context.accentColor),
      ),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 2,
      heroAttributes: PhotoViewHeroAttributes(tag: url),
    );
  }

  Widget _buildVideoPlayer() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Center(child: CircularProgressIndicator(color: context.accentColor));
    }

    return AspectRatio(
      aspectRatio: _videoController!.value.aspectRatio,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(_videoController!),
          VideoProgressIndicator(_videoController!, allowScrubbing: true),
          GestureDetector(
            onTap: () {
              setState(() {
                _videoController!.value.isPlaying
                    ? _videoController!.pause()
                    : _videoController!.play();
              });
            },
            child: Center(
              child: Icon(
                _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white.withValues(alpha: 0.5),
                size: 80,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _CircleButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 24),
        onPressed: onPressed,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color ?? Colors.white, size: 30),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTypography.inter(
              color: color ?? Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
