import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:lynk_core/core.dart';

class SingleMediaView extends StatefulWidget {
  final String url;
  final String mediaType;
  final bool isActive;

  const SingleMediaView({super.key, 
    required this.url,
    required this.mediaType,
    this.isActive = true,
  });

  @override
  State<SingleMediaView> createState() => _SingleMediaViewState();
}

class _SingleMediaViewState extends State<SingleMediaView> {
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  double? _imageWidth;
  double? _imageHeight;
  bool _imageLoaded = false;
  bool _imageError = false;

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.url);
    final ext = uri?.path.split('.').last.toLowerCase() ?? '';
    _isVideo = widget.mediaType == 'video' ||
        const {'mp4', 'webm', 'mov', 'm4v', '3gp', 'mkv'}.contains(ext) ||
        widget.url.contains('.mp4');
    
    if (_isVideo) {
      _initVideo();
    } else {
      _resolveImageSize();
    }
  }

  void _initVideo() {
    _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          if (widget.isActive) {
            _videoController?.play();
            _videoController?.setLooping(true);
          }
        }
      }).catchError((error) {
        debugPrint('[MediaViewer] Video initialize error: $error');
        if (mounted) {
          setState(() {});
        }
      });
  }

  @override
  void didUpdateWidget(SingleMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isVideo && _videoController != null && _videoController!.value.isInitialized) {
      if (!widget.isActive && oldWidget.isActive) {
        _videoController?.pause();
      } else if (widget.isActive && !oldWidget.isActive) {
        _videoController?.play();
      }
    }
  }

  void _resolveImageSize() {
    final imageProvider = NetworkImage(widget.url);
    final ImageStream stream = imageProvider.resolve(const ImageConfiguration());
    ImageStreamListener? listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        if (mounted) {
          setState(() {
            _imageWidth = info.image.width.toDouble();
            _imageHeight = info.image.height.toDouble();
            _imageLoaded = true;
            _imageError = false;
          });
        }
        if (listener != null) {
          stream.removeListener(listener);
        }
      },
      onError: (exception, stackTrace) {
        if (mounted) {
          setState(() {
            _imageLoaded = true;
            _imageError = true;
          });
        }
        if (listener != null) {
          stream.removeListener(listener);
        }
      },
    );
    stream.addListener(listener);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVideo) {
      if (_imageError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image, size: 48, color: Colors.white24),
              const SizedBox(height: 12),
              Text(
                'Failed to load media',
                style: AppTypography.inter(fontSize: 13, color: Colors.white54),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _imageLoaded = false;
                    _imageError = false;
                  });
                  _resolveImageSize();
                },
                child: Text('Retry', style: TextStyle(color: context.accentColor)),
              ),
            ],
          ),
        );
      }

      if (!_imageLoaded || _imageWidth == null || _imageHeight == null) {
        return Center(
          child: CircularProgressIndicator(color: context.accentColor),
        );
      }

      final aspectRatio = _imageWidth! / _imageHeight!;

      return Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            children: [
              PhotoView(
                imageProvider: NetworkImage(widget.url),
                backgroundDecoration: const BoxDecoration(color: Colors.transparent),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 2,
                heroAttributes: PhotoViewHeroAttributes(tag: widget.url),
              ),
            ],
          ),
        ),
      );
    }

    if (_videoController == null || !_videoController!.value.isInitialized) {
      if (_videoController?.value.hasError == true) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.white24),
              const SizedBox(height: 12),
              Text(
                'Failed to play video',
                style: AppTypography.inter(fontSize: 13, color: Colors.white54),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  _videoController?.dispose();
                  setState(() {
                    _initVideo();
                  });
                },
                child: Text('Retry', style: TextStyle(color: context.accentColor)),
              ),
            ],
          ),
        );
      }
      return Center(child: CircularProgressIndicator(color: context.accentColor));
    }

    return Center(
      child: AspectRatio(
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
      ),
    );
  }
}
