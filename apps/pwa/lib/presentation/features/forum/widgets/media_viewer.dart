import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_core/core.dart';

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
        
    ForumMediaCubit? forumMediaCubit;
    ForumCubit? forumCubit;
    try {
      forumMediaCubit = context.read<ForumMediaCubit>();
      forumCubit = context.read<ForumCubit>();
    } catch (_) {}

    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          Widget viewer = MediaViewer(
            imageUrl: imageUrl,
            mediaItem: mediaItem,
            onMention: onMention,
            onApprove: onApprove,
          );
          if (forumMediaCubit != null) {
            viewer = BlocProvider.value(value: forumMediaCubit, child: viewer);
          }
          if (forumCubit != null) {
            viewer = BlocProvider.value(value: forumCubit, child: viewer);
          }
          return viewer;
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late PageController _pageController;
  int _currentIndex = 0;
  List<ForumMedia> _gallery = [];
  bool _isStandalone = true;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      BrowserContextMenu.disableContextMenu();
    }

    try {
      final mediaCubit = context.read<ForumMediaCubit>();
      _gallery = mediaCubit.state.mediaItems;
    } catch (_) {
      _gallery = [];
    }

    final urlToFind = widget.mediaItem?.url ?? widget.imageUrl;
    int index = _gallery.indexWhere((m) => m.url == urlToFind);

    if (index != -1) {
      _currentIndex = index;
      _isStandalone = false;
    } else {
      _currentIndex = 0;
      _isStandalone = true;
      if (widget.mediaItem != null) {
        _gallery = [widget.mediaItem!];
      } else if (widget.imageUrl != null) {
        _gallery = [
          ForumMedia(
            id: 'standalone',
            url: widget.imageUrl!,
            mediaType: widget.imageUrl!.contains('.mp4') ? 'video' : 'image',
            uploaderId: 'user',
            createdAt: DateTime.now(),
            isApproved: true,
          )
        ];
      }
    }

    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    if (kIsWeb) {
      BrowserContextMenu.enableContextMenu();
    }
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });

    if (!_isStandalone) {
      try {
        final state = context.read<ForumMediaCubit>().state;
        if (index >= state.mediaItems.length - 2) {
          context.read<ForumMediaCubit>().loadMore();
        }
      } catch (_) {}
    }
  }

  Future<void> _downloadMedia() async {
    if (_gallery.isEmpty) return;
    final targetUrl = _gallery[_currentIndex].url;
    final uri = Uri.tryParse(targetUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _nextPage() {
    if (_currentIndex < _gallery.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevPage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isPremium = false;
    try {
      isPremium = context.read<ForumCubit>().state.isPremium;
    } catch (_) {}

    return Scaffold(
      backgroundColor: Colors.black,
      body: BlocConsumer<ForumMediaCubit, ForumMediaState>(
        listener: (context, state) {
          if (!_isStandalone) {
            setState(() {
              _gallery = state.mediaItems;
            });
          }
        },
        builder: (context, state) {
          final currentMedia = _gallery.isNotEmpty && _currentIndex < _gallery.length 
              ? _gallery[_currentIndex] 
              : null;

          return Stack(
            children: [
              // Content Area (PageView)
              if (_gallery.isNotEmpty)
                PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  itemCount: _gallery.length,
                  itemBuilder: (context, index) {
                    final media = _gallery[index];
                    return _SingleMediaView(
                      url: media.url,
                      mediaType: media.mediaType,
                    );
                  },
                )
              else
                const Center(child: Icon(Icons.broken_image, color: Colors.white24)),
              
              // Anti-piracy Watermark
              // Disabled for premium members
              if (!isPremium)
                IgnorePointer(
                  child: _buildWatermark(),
                ),

              // Navigation Chevrons (Desktop/Web only)
              if (kIsWeb && _gallery.length > 1)
                Positioned.fill(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentIndex > 0)
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 50, color: Colors.white),
                          onPressed: _prevPage,
                        )
                      else
                        const SizedBox(width: 64),
                      if (_currentIndex < _gallery.length - 1)
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 50, color: Colors.white),
                          onPressed: _nextPage,
                        )
                      else
                        const SizedBox(width: 64),
                    ],
                  ),
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
                    if (currentMedia != null)
                      Text(
                        currentMedia.mediaType.toUpperCase(),
                        style: AppTypography.inter(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // _CircleButton(
                        //   icon: Icons.alternate_email,
                        //   onPressed: () {
                        //     Navigator.pop(context);
                        //     widget.onMention?.call();
                        //   },
                        // ),
                        // const SizedBox(width: 8),
                        _CircleButton(
                          icon: Icons.download_rounded,
                          onPressed: _downloadMedia,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Bottom Actions
              if (widget.onApprove != null)
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + 30,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ActionButton(
                        icon: Icons.check_circle_outline,
                        label: 'Approve',
                        color: Colors.greenAccent,
                        onTap: () {
                          widget.onApprove?.call();
                          Navigator.pop(context);
                        },
                      ),
                      const SizedBox(width: 16),
                      _ActionButton(
                        icon: Icons.delete_outline,
                        label: 'Reject',
                        color: Colors.redAccent,
                        onTap: () {
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWatermark() {
    const double baseDensity = 0.25; 

    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = (constraints.maxWidth / 80).ceil();
          final rowCount = (constraints.maxHeight / 80).ceil();
          final totalCount = crossAxisCount * rowCount;

          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount > 0 ? crossAxisCount : 1,
              childAspectRatio: 1.0,
            ),
            itemCount: totalCount,
            itemBuilder: (context, index) {
              final pseudoRandom = ((index * 37) + 11) % 100 / 100.0;
              
              if (pseudoRandom > baseDensity) {
                return const SizedBox.shrink();
              }

              final alphaValue = (0.15 + (pseudoRandom * 0.15)).clamp(0.0, 1.0);

              return Center(
                child: Text(
                  'X',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: alphaValue),
                    fontSize: 20 + (pseudoRandom * 30), 
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: alphaValue * 1.5),
                        offset: const Offset(2, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }
      ),
    );
  }
}

class _SingleMediaView extends StatefulWidget {
  final String url;
  final String mediaType;

  const _SingleMediaView({required this.url, required this.mediaType});

  @override
  State<_SingleMediaView> createState() => _SingleMediaViewState();
}

class _SingleMediaViewState extends State<_SingleMediaView> {
  VideoPlayerController? _videoController;
  bool _isVideo = false;

  @override
  void initState() {
    super.initState();
    _isVideo = widget.mediaType == 'video' || widget.url.contains('.mp4');
    
    if (_isVideo) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.url))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            _videoController?.play();
            _videoController?.setLooping(true);
          }
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVideo) {
      return PhotoView(
        imageProvider: NetworkImage(widget.url),
        loadingBuilder: (context, event) => Center(
          child: CircularProgressIndicator(color: context.accentColor),
        ),
        backgroundDecoration: const BoxDecoration(color: Colors.transparent),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2,
        heroAttributes: PhotoViewHeroAttributes(tag: widget.url),
      );
    }

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
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.inter(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
