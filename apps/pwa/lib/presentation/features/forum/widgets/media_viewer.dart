import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_ads_cubit.dart';
import 'package:lynk_x/presentation/features/forum/widgets/interstitial_ad.dart';
import 'package:lynk_x/core/utils/download_helper.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

class MediaViewer extends StatefulWidget {
  final String? imageUrl;
  final ForumMedia? mediaItem;
  final VoidCallback? onMention;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const MediaViewer({
    super.key,
    this.imageUrl,
    this.mediaItem,
    this.onMention,
    this.onApprove,
    this.onReject,
  });

  static void show(BuildContext context,
      {String? imageUrl,
      ForumMedia? mediaItem,
      VoidCallback? onMention,
      VoidCallback? onApprove,
      VoidCallback? onReject}) {
        
    ForumMediaCubit? forumMediaCubit;
    ForumCubit? forumCubit;
    ForumAdsCubit? forumAdsCubit;
    try {
      forumMediaCubit = context.read<ForumMediaCubit>();
      forumCubit = context.read<ForumCubit>();
    } catch (_) {}
    try {
      forumAdsCubit = context.read<ForumAdsCubit>();
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
            onReject: onReject,
          );
          if (forumMediaCubit != null) {
            viewer = BlocProvider.value(value: forumMediaCubit, child: viewer);
          }
          if (forumCubit != null) {
            viewer = BlocProvider.value(value: forumCubit, child: viewer);
          }
          if (forumAdsCubit != null) {
            viewer = BlocProvider.value(value: forumAdsCubit, child: viewer);
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

  /// Builds a filename like "Summer_Fest_Photo_3.jpg": the forum/event name,
  /// sanitized to safe filesystem characters, plus the media's 1-based
  /// gallery position, plus the original file extension (the only part of
  /// the server-provided name worth keeping — everything else is typically
  /// an opaque storage key).
  String _buildFilename(ForumMedia media, int index) {
    String forumName = 'Forum';
    try {
      forumName = context.read<ForumCubit>().state.forumName;
    } catch (_) {}

    final sanitizedName = forumName
        .trim()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    final safeName = sanitizedName.isEmpty ? 'Forum' : sanitizedName;

    final label = media.mediaType == 'video' ? 'Video' : 'Photo';

    String extension = media.mediaType == 'video' ? 'mp4' : 'jpg';
    final uri = Uri.tryParse(media.url);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final lastSegment = uri.pathSegments.last;
      final dotIndex = lastSegment.lastIndexOf('.');
      if (dotIndex != -1 && dotIndex < lastSegment.length - 1) {
        final candidate = lastSegment.substring(dotIndex + 1).toLowerCase();
        // Guard against picking up a query-param fragment or an unreasonably
        // long "extension" from an opaque storage key with dots in it.
        if (candidate.length <= 5 && RegExp(r'^[a-z0-9]+$').hasMatch(candidate)) {
          extension = candidate;
        }
      }
    }

    return '${safeName}_${label}_${index + 1}.$extension';
  }

  Future<void> _downloadMedia() async {
    if (_gallery.isEmpty) return;
    final media = _gallery[_currentIndex];
    final targetUrl = media.url;
    final uri = Uri.tryParse(targetUrl);
    if (uri == null) return;

    ForumAdsCubit? adsCubit;
    try {
      adsCubit = context.read<ForumAdsCubit>();
    } catch (_) {}

    if (adsCubit != null && adsCubit.shouldShowDownloadInterstitial()) {
      final ad = adsCubit.state.interstitialAd;
      if (ad != null && mounted) {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => InterstitialAd(
              ad: ad,
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
        );
      }
    }

    if (!mounted) return;
    await _startDownload(targetUrl, media);
  }

  Future<void> _startDownload(String targetUrl, ForumMedia media) async {
    AppSnackBars.showInfo(context, 'Starting download...');

    final filename = _buildFilename(media, _currentIndex);

    try {
      final result = await downloadFile(targetUrl, filename);
      if (!mounted) return;
      if (result.openedInNewTab) {
        AppSnackBars.showInfo(
          context,
          'Opened in a new tab — use your browser\'s Save/Download option to save it.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.showError(context, 'Download failed: ${e.toString()}');
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

          bool isOrganizer = false;
          bool isModerator = false;
          String? currentUserId;
          try {
            final forumCubit = context.read<ForumCubit>();
            isOrganizer = forumCubit.state.isOrganizer;
            isModerator = forumCubit.state.isModerator;
            currentUserId = forumCubit.userId;
          } catch (_) {}

          final hasCubit = currentMedia != null && currentUserId != null;
          final isAuthorized = isOrganizer || isModerator;
          final isUploader = hasCubit && currentMedia.uploaderId == currentUserId;

          final showApprove = hasCubit ? (isAuthorized && !currentMedia.isApproved) : (widget.onApprove != null);
          final showDelete = hasCubit ? (isAuthorized || isUploader) : (widget.onReject != null);
          // A moderator's bottom-bar action is "Reject" while the item is
          // still pending review, but "Delete" once it's already approved —
          // otherwise the label implies the item was never reviewed even
          // when it's live and being removed after the fact.
          final deleteText = (hasCubit && isUploader && !isAuthorized)
              ? 'Delete'
              : (hasCubit && isAuthorized && currentMedia.isApproved)
                  ? 'Delete'
                  : 'Reject';

          return Column(
            children: [
              SafeArea(
                bottom: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: Colors.black,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          currentMedia != null
                              ? '${currentMedia.mediaType.toUpperCase()} (${_currentIndex + 1}/${_gallery.length})'
                              : 'MEDIA VIEWER',
                          style: AppTypography.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.download_rounded, color: Colors.white),
                        onPressed: _downloadMedia,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Stack(
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
                            isPremium: isPremium,
                          );
                        },
                      )
                    else
                      const Center(child: Icon(Icons.broken_image, color: Colors.white24)),

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

                  ],
                ),
              ),

              // Attribution row — sits on the viewer's own dark chrome
              // background rather than overlaid on the media, so it stays
              // legible regardless of what's in the photo/video underneath.
              if (currentMedia != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: _MediaAttribution(
                          media: currentMedia,
                          isUploader: isUploader,
                        ),
                      ),
                      // Members with no moderation authority get their own
                      // action here instead of the bottom Approve/Reject bar
                      // (which stays organizer/moderator-only) — Delete for
                      // their own upload, Report for anyone else's.
                      if (!isAuthorized && currentUserId != null) ...[
                        const SizedBox(width: 8),
                        _MediaMemberAction(
                          isUploader: isUploader,
                          onDelete: () {
                            if (!hasCubit) return;
                            try {
                              context.read<ForumMediaCubit>().deleteMedia(currentMedia);
                            } catch (_) {}
                          },
                          onReport: (reason) {
                            if (!hasCubit) return;
                            try {
                              context.read<ForumMediaCubit>().reportMedia(currentMedia, reason);
                              AppSnackBars.showSuccess(context, 'Media reported.');
                            } catch (_) {}
                          },
                        ),
                      ],
                    ],
                  ),
                ),

              // Bottom Actions
              if (showApprove || showDelete)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 20,
                    left: 24,
                    right: 24,
                    top: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Reject/Delete is outlined and Approve is filled —
                      // establishes Approve as the expected path (most
                      // reviews end in approval) without hiding Reject or
                      // requiring a confirmation dialog for it.
                      if (showDelete) ...[
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              label: Text(
                                deleteText,
                                style: AppTypography.interTight(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white54,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                if (hasCubit) {
                                  try {
                                    context.read<ForumMediaCubit>().deleteMedia(currentMedia);
                                  } catch (_) {}
                                } else {
                                  widget.onReject?.call();
                                }
                                Navigator.pop(context);
                              },
                            ),
                          ),
                        ),
                        if (showApprove) const SizedBox(width: 16),
                      ],
                      if (showApprove)
                        Expanded(
                          child: PrimaryButton(
                            icon: Icons.check_circle_outline,
                            text: 'Approve',
                            backgroundColor: context.accentColor,
                            textColor: Colors.black,
                            onPressed: () {
                              if (hasCubit) {
                                try {
                                  context.read<ForumMediaCubit>().approveMedia(currentMedia);
                                } catch (_) {}
                              } else {
                                widget.onApprove?.call();
                              }
                              Navigator.pop(context);
                            },
                          ),
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

}

/// "Shared by [name] · [relative time]" caption shown below the media, in
/// the viewer's own column (not overlaid on the image). Omits the "Shared
/// by" clause entirely (rather than showing a blank name) when uploaderName
/// isn't available — e.g. a realtime-inserted item whose flat payload has no
/// joined profile until the next refreshMedia() fetch.
class _MediaAttribution extends StatelessWidget {
  final ForumMedia media;
  final bool isUploader;

  const _MediaAttribution({required this.media, required this.isUploader});

  @override
  Widget build(BuildContext context) {
    final relativeTime = timeago.format(media.createdAt, locale: 'en_short');
    final uploaderName = media.uploaderName;
    final displayName = isUploader ? 'You' : uploaderName;
    final text = displayName != null && displayName.isNotEmpty
        ? 'Shared by $displayName · $relativeTime'
        : relativeTime;

    return Text(
      text,
      style: AppTypography.inter(
        fontSize: 11,
        color: Colors.white.withValues(alpha: 0.75),
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Non-authorized members' single action next to the attribution chip:
/// Delete for their own upload, Report for anyone else's. Organizers/
/// moderators never see this — they use the bottom Approve/Reject bar
/// instead, so the same person never gets two different ways to remove
/// the same item.
class _MediaMemberAction extends StatelessWidget {
  final bool isUploader;
  final VoidCallback onDelete;
  final ValueChanged<String> onReport;

  const _MediaMemberAction({
    required this.isUploader,
    required this.onDelete,
    required this.onReport,
  });

  void _confirmDelete(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this upload?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will be removed for everyone.',
          style: TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) onDelete();
    });
  }

  void _showReportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report this media',
                style: AppTypography.interTight(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              ...['Spam', 'Harassment', 'Inappropriate Content'].map((reason) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(reason, style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    onReport(reason);
                    Navigator.pop(bottomSheetContext);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => isUploader ? _confirmDelete(context) : _showReportSheet(context),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isUploader ? Icons.delete_outline : Icons.flag_outlined,
          size: 15,
          color: Colors.white.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

class _SingleMediaView extends StatefulWidget {
  final String url;
  final String mediaType;
  final bool isPremium;

  const _SingleMediaView({
    required this.url,
    required this.mediaType,
    required this.isPremium,
  });

  @override
  State<_SingleMediaView> createState() => _SingleMediaViewState();
}

class _SingleMediaViewState extends State<_SingleMediaView> {
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  double? _imageWidth;
  double? _imageHeight;
  bool _imageLoaded = false;

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
    } else {
      _resolveImageSize();
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
              if (!widget.isPremium)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: ForumMediaWatermark(),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Center(child: CircularProgressIndicator(color: context.accentColor));
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            VideoPlayer(_videoController!),
            if (!widget.isPremium)
              const Positioned.fill(
                child: IgnorePointer(
                  child: ForumMediaWatermark(),
                ),
              ),
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

class ForumMediaWatermark extends StatelessWidget {
  const ForumMediaWatermark({super.key});

  @override
  Widget build(BuildContext context) {
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

