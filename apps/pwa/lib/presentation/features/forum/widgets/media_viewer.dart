import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_ads_cubit.dart';
import 'package:lynk_x/presentation/features/forum/widgets/interstitial_ad.dart';
import 'package:lynk_x/core/utils/download_helper.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import 'media_viewer_overlays.dart';
import 'single_media_view.dart';

class MediaViewer extends StatefulWidget {
  final String? imageUrl;
  final ForumMedia? mediaItem;
  final void Function(ForumMedia)? onMention;

  /// Sends [text] to Live Chat with the photo attached, without leaving the viewer. Null hides the quick comment
  /// box (chat switched off for the forum). Returns whether the message was accepted.
  final Future<bool> Function(ForumMedia media, String text)? onSendComment;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const MediaViewer({
    super.key,
    this.imageUrl,
    this.mediaItem,
    this.onMention,
    this.onSendComment,
    this.onApprove,
    this.onReject,
  });

  static void show(BuildContext context,
      {String? imageUrl,
      ForumMedia? mediaItem,
      void Function(ForumMedia)? onMention,
      Future<bool> Function(ForumMedia media, String text)? onSendComment,
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
            onSendComment: onSendComment,
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
        if (candidate.length <= 5 &&
            RegExp(r'^[a-z0-9]+$').hasMatch(candidate)) {
          extension = candidate;
        }
      }
    }

    return '${safeName}_${label}_${index + 1}.$extension';
  }

  bool get _isAuthorized {
    try {
      final forumCubit = context.read<ForumCubit>();
      return forumCubit.state.isOrganizer || forumCubit.state.isModerator;
    } catch (_) {
      return false;
    }
  }

  /// Prompts a modal sheet gating downloads when public distribution rights
  /// have been revoked or restricted by the uploader or a pictured attendee.
  Future<bool> _showDistributionConsentSheet(
    BuildContext context,
    ForumMedia media,
  ) async {
    final isAuthorized = _isAuthorized;
    final isVideo = media.mediaType == 'video';
    final mediaLabel = isVideo ? 'video' : 'photo';

    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF161616),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: Colors.white12, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Colors.amberAccent,
                  size: 30,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Distribution Rights Restricted',
                style: AppTypography.interTight(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                isAuthorized
                    ? 'The uploader or a pictured attendee has restricted external distribution for this $mediaLabel.\n\nAs an organizer, you may download a copy for archival or administrative records, but public redistribution or commercial use is prohibited.'
                    : 'The uploader or a pictured attendee has restricted external distribution for this $mediaLabel.\n\nBy downloading, you agree this copy is strictly for personal, private viewing and will not be shared, posted on social media, or distributed elsewhere.',
                style: AppTypography.inter(
                  fontSize: 14,
                  color: Colors.white70,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                text: 'Agree & Download',
                backgroundColor: context.accentColor,
                textColor: Colors.black,
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                child: Text(
                  'Cancel',
                  style: AppTypography.inter(
                    color: Colors.white38,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return result ?? false;
  }

  Future<void> _downloadMedia() async {
    if (_gallery.isEmpty) return;
    final media = _gallery[_currentIndex];
    final targetUrl = media.url;
    final uri = Uri.tryParse(targetUrl);
    if (uri == null) return;

    // Enforce distribution rights: If external rights are revoked or restricted,
    // require an explicit consent/permission acknowledgment before downloading.
    if (!media.hasDistributionRights) {
      final confirmed = await _showDistributionConsentSheet(context, media);
      if (!confirmed || !mounted) return;
    }

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
      AppSnackBars.showError(
          context, 'Download failed: ${e.toFriendlyMessage()}');
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
    // This route is pushed imperatively (Navigator.push, not a go_router
    // route — see MediaViewer.show above), sitting on top of go_router's
    // own managed stack. Without this, the system back gesture/button was
    // observed landing on the home page instead of returning to the media
    // tab the viewer was opened from — most likely go_router's own
    // back-handling reconciling its route stack around this un-routed
    // page rather than just popping it. Intercepting the pop here and
    // always funneling it through the identical Navigator.pop(context)
    // the close button already uses (not rootNavigator: true, matching
    // the close button exactly) makes every dismissal path behave the
    // same, regardless of what triggered it.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
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
            final currentMedia =
                _gallery.isNotEmpty && _currentIndex < _gallery.length
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
            final isUploader =
                hasCubit && currentMedia.uploaderId == currentUserId;

            final canMentionInChat = widget.onMention != null &&
                currentMedia != null &&
                currentMedia.isApproved;

            final showApprove = hasCubit
                ? (isAuthorized && !currentMedia.isApproved)
                : (widget.onApprove != null);
            final showDelete = hasCubit
                ? ((isAuthorized && !currentMedia.isApproved) ||
                    (isUploader && !isAuthorized))
                : (widget.onReject != null);
            // A moderator's bottom-bar action is "Reject" while the item is
            // still pending review, but "Delete" once it's already approved —
            // otherwise the label implies the item was never reviewed even
            // when it's live and being removed after the fact. Organizers
            // must not see the large delete button for already-approved media
            // they uploaded; only non-organizer uploaders or pending review
            // items can be removed via the bottom bar.
            final deleteText = (hasCubit && isUploader && !isAuthorized)
                ? 'Delete'
                : (hasCubit && isAuthorized && !currentMedia.isApproved)
                    ? 'Reject'
                    : 'Delete';

            return Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Container(
                    // The icon buttons carry their own 10 px padding (a 44 px touch target), so the bar itself has
                    // no side padding and the icons sit 10 px from the screen edge instead of 16.
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    color: Colors.black,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          padding: const EdgeInsets.all(10),
                          constraints:
                              const BoxConstraints(minWidth: 44, minHeight: 44),
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            currentMedia != null
                                ? '${currentMedia.mediaType.toUpperCase()} (${_currentIndex + 1}/${_gallery.length})'
                                : 'MEDIA VIEWER',
                            textAlign: TextAlign.center,
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
                          padding: const EdgeInsets.all(10),
                          constraints:
                              const BoxConstraints(minWidth: 44, minHeight: 44),
                          icon: const Icon(Icons.download_rounded,
                              color: Colors.white),
                          tooltip: 'Download',
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
                            return SingleMediaView(
                              url: media.url,
                              mediaType: media.mediaType,
                              isActive: index == _currentIndex,
                            );
                          },
                        )
                      else
                        const Center(
                            child: Icon(Icons.broken_image,
                                color: Colors.white24)),

                      // Navigation Chevrons (Desktop/Web only)
                      if (kIsWeb && _gallery.length > 1)
                        Positioned.fill(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (_currentIndex > 0)
                                IconButton(
                                  icon: const Icon(Icons.chevron_left,
                                      size: 50, color: Colors.white),
                                  onPressed: _prevPage,
                                )
                              else
                                const SizedBox(width: 64),
                              if (_currentIndex < _gallery.length - 1)
                                IconButton(
                                  icon: const Icon(Icons.chevron_right,
                                      size: 50, color: Colors.white),
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
                    padding: EdgeInsets.fromLTRB(
                      24,
                      6,
                      24,
                      6 +
                          (showApprove || showDelete
                              ? 0
                              : MediaQuery.of(context).padding.bottom),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Left: Direct 1-tap Live Chat discuss/reply action
                        if (canMentionInChat)
                          GestureDetector(
                            key: const Key('media-viewer-reply-chat'),
                            onTap: () {
                              Navigator.pop(context);
                              widget.onMention?.call(currentMedia);
                            },
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.reply_rounded,
                                size: 18,
                                color: Colors.white70,
                              ),
                            ),
                          )
                        else
                          const SizedBox(width: 30),
                        const SizedBox(width: 8),
                        Flexible(
                          child: MediaAttribution(
                            media: currentMedia,
                            isUploader: isUploader,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Members and organizers get an action menu next to the attribution chip:
                        // - Uploader: Distribution rights toggle & Delete
                        // - Attendee: Revoke distribution rights & Report Violation
                        // - Organizer: Distribution rights toggle & Moderator controls
                        if (currentUserId != null)
                          MediaMemberAction(
                            media: currentMedia,
                            isUploader: isUploader,
                            isAuthorized: isAuthorized,
                            onDelete: () async {
                              if (!hasCubit) return;
                              final success = await context
                                  .read<ForumMediaCubit>()
                                  .deleteMedia(currentMedia);
                              if (!context.mounted) return;
                              if (success) {
                                Navigator.pop(context);
                              } else {
                                AppSnackBars.showError(context,
                                    'Failed to delete media. Please try again.');
                              }
                            },
                            onRevokeDistributionRights: () async {
                              if (!hasCubit) return;
                              final success = await context
                                  .read<ForumMediaCubit>()
                                  .revokeDistributionRights(currentMedia);
                              if (!context.mounted) return;
                              if (success) {
                                AppSnackBars.showSuccess(context,
                                    'Distribution rights revoked for this photo.');
                              } else {
                                AppSnackBars.showError(context,
                                    'Couldn\'t update distribution rights. Please try again.');
                              }
                            },
                            onToggleDistributionRights: (eligible) async {
                              if (!hasCubit) return;
                              final success = await context
                                  .read<ForumMediaCubit>()
                                  .setDistributionRights(
                                      currentMedia, eligible);
                              if (!context.mounted) return;
                              if (success) {
                                AppSnackBars.showSuccess(
                                  context,
                                  eligible
                                      ? 'Distribution rights granted for this photo.'
                                      : 'Distribution rights revoked for this photo.',
                                );
                              } else {
                                AppSnackBars.showError(context,
                                    'Couldn\'t update distribution rights. Please try again.');
                              }
                            },
                            onReport: (reasonId) async {
                              if (!hasCubit) return;
                              try {
                                await context
                                    .read<ForumMediaCubit>()
                                    .reportMedia(currentMedia, reasonId);
                                if (!context.mounted) return;
                                if (reasonId == 'likeness_no_consent') {
                                  Navigator.pop(context);
                                  AppSnackBars.showSuccess(
                                    context,
                                    'Photo reported and hidden pending review.',
                                  );
                                } else {
                                  AppSnackBars.showSuccess(
                                      context, 'Media reported.');
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  AppSnackBars.showError(context,
                                      'Failed to submit report. Please try again.');
                                }
                              }
                            },
                          )
                        else
                          const SizedBox(width: 30),
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
                                icon:
                                    const Icon(Icons.delete_outline, size: 20),
                                label: Text(
                                  deleteText,
                                  style: AppTypography.interTight(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white54,
                                  side: BorderSide(
                                      color:
                                          Colors.white.withValues(alpha: 0.16)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () {
                                  Future<void> performReject() async {
                                    if (hasCubit) {
                                      final success = await context
                                          .read<ForumMediaCubit>()
                                          .deleteMedia(currentMedia);
                                      if (!context.mounted) return;
                                      if (success) {
                                        Navigator.pop(context);
                                      } else {
                                        AppSnackBars.showError(context,
                                            'Failed to remove media. Please try again.');
                                      }
                                    } else {
                                      widget.onReject?.call();
                                      Navigator.pop(context);
                                    }
                                  }

                                  // Rejecting a still-pending item is instant —
                                  // nothing was ever visible to other members.
                                  // Deleting an already-approved (live) item
                                  // needs confirmation first, same as the
                                  // member-facing delete flow.
                                  final isDestructiveDelete = hasCubit &&
                                      isAuthorized &&
                                      currentMedia.isApproved;
                                  if (isDestructiveDelete) {
                                    showMediaDeleteConfirmation(
                                        context, performReject);
                                  } else {
                                    performReject();
                                  }
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
                              onPressed: () async {
                                if (hasCubit) {
                                  final success = await context
                                      .read<ForumMediaCubit>()
                                      .approveMedia(currentMedia);
                                  if (!context.mounted) return;
                                  if (success) {
                                    Navigator.pop(context);
                                  } else {
                                    AppSnackBars.showError(context,
                                        'Failed to approve media. Please try again.');
                                  }
                                } else {
                                  widget.onApprove?.call();
                                  Navigator.pop(context);
                                }
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
      ),
    );
  }
}
