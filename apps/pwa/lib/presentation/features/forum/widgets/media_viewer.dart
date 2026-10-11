import 'package:flutter/material.dart';
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
import 'package:lynk_x/presentation/features/forum/core/media_comment_rules.dart';
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
  final TextEditingController _commentController = TextEditingController();
  bool _isSendingComment = false;

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
    _commentController.dispose();
    if (kIsWeb) {
      BrowserContextMenu.enableContextMenu();
    }
    super.dispose();
  }

  void _onPageChanged(int index) {
    // A half-typed comment belongs to the photo it was written under, so it is dropped rather than carried over.
    _commentController.clear();
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
      AppSnackBars.showError(context, 'Download failed: ${e.toFriendlyMessage()}');
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

  /// Sends the quick comment under [media] to Live Chat and keeps the viewer open.
  Future<void> _sendComment(ForumMedia media) async {
    final text = _commentController.text.trim();
    final send = widget.onSendComment;
    if (text.isEmpty || send == null || _isSendingComment) return;

    setState(() => _isSendingComment = true);
    final sent = await send(media, text);
    if (!mounted) return;
    setState(() => _isSendingComment = false);

    if (sent) {
      _commentController.clear();
      FocusScope.of(context).unfocus();
      AppSnackBars.showSuccess(context, 'Sent to Live Chat');
    } else {
      AppSnackBars.showError(context, 'Could not send your comment. Please try again.');
    }
  }

  /// The quick comment box under the photo: type, send, and the message goes to Live Chat with this photo attached.
  /// [bottomInset] adds the device's safe-area space when nothing sits below it.
  Widget _buildCommentBox(ForumMedia media, {required bool bottomInset}) {
    final noun = media.mediaType == 'video' ? 'video' : 'photo';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        bottomInset ? MediaQuery.of(context).padding.bottom + 12 : 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                key: const Key('media-viewer-comment-field'),
                controller: _commentController,
                enabled: !_isSendingComment,
                cursorColor: AppColors.secondaryText,
                style: AppTypography.inter(color: AppColors.secondaryText),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendComment(media),
                decoration: InputDecoration(
                  hintText: 'Say something about this $noun',
                  hintStyle: AppTypography.inter(
                      color: AppColors.secondaryText.withValues(alpha: 0.5)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _commentController,
            builder: (context, value, _) {
              final canSend = value.text.trim().isNotEmpty && !_isSendingComment;
              return Semantics(
                button: true,
                label: 'Send to Live Chat',
                child: IconButton.filled(
                  key: const Key('media-viewer-comment-send'),
                  onPressed: canSend ? () => _sendComment(media) : null,
                  style: IconButton.styleFrom(
                    backgroundColor: context.accentColor,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white12,
                    minimumSize: const Size(44, 44),
                  ),
                  icon: _isSendingComment
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                ),
              );
            },
          ),
        ],
      ),
    );
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

          // The quick comment box follows the chat composer's own rules: it never shows to guests, in an archived
          // or read-only forum (organizers excepted, as in the composer), or to a muted member, and only for
          // approved media, since pending items are not visible to the forum yet.
          var forumReadOnly = false;
          var forumArchived = false;
          var forumMuted = false;
          try {
            final forumState = context.read<ForumCubit>().state;
            forumReadOnly = forumState.isReadOnly;
            forumArchived = forumState.isArchived;
            forumMuted = forumState.isMuted;
          } catch (_) {}
          final canComment = canCommentOnMedia(
            chatEnabled: widget.onSendComment != null,
            mediaId: currentMedia?.id,
            mediaApproved: currentMedia?.isApproved ?? false,
            userId: currentUserId,
            isGuest: currentUserId != null && isGuestUser(currentUserId),
            isOrganizer: isOrganizer,
            forumReadOnly: forumReadOnly,
            forumArchived: forumArchived,
            isMuted: forumMuted,
          );

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
                  // The icon buttons carry their own 10 px padding (a 44 px touch target), so the bar itself has
                  // no side padding and the icons sit 10 px from the screen edge instead of 16.
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  color: Colors.black,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        padding: const EdgeInsets.all(10),
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        icon: const Icon(Icons.download_rounded, color: Colors.white),
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
                        child: MediaAttribution(
                          media: currentMedia,
                          isUploader: isUploader,
                        ),
                      ),
                      // Members and organizers get an action menu next to the attribution chip:
                      // - Uploader: Distribution rights toggle & Delete
                      // - Attendee: Revoke distribution rights & Report Violation
                      // - Organizer: Distribution rights toggle & Moderator controls
                      if (currentUserId != null) ...[
                        const SizedBox(width: 8),
                        MediaMemberAction(
                          media: currentMedia,
                          isUploader: isUploader,
                          isAuthorized: isAuthorized,
                          onMention: widget.onMention,
                          onDelete: () async {
                            if (!hasCubit) return;
                            final success = await context.read<ForumMediaCubit>().deleteMedia(currentMedia);
                            if (!context.mounted) return;
                            if (success) {
                              Navigator.pop(context);
                            } else {
                              AppSnackBars.showError(context, 'Failed to delete media. Please try again.');
                            }
                          },
                          onRevokeDistributionRights: () async {
                            if (!hasCubit) return;
                            final success = await context.read<ForumMediaCubit>().revokeDistributionRights(currentMedia);
                            if (!context.mounted) return;
                            if (success) {
                              AppSnackBars.showSuccess(context, 'Distribution rights revoked for this photo.');
                            } else {
                              AppSnackBars.showError(context, 'Couldn\'t update distribution rights. Please try again.');
                            }
                          },
                          onToggleDistributionRights: (eligible) async {
                            if (!hasCubit) return;
                            final success = await context.read<ForumMediaCubit>().setDistributionRights(currentMedia, eligible);
                            if (!context.mounted) return;
                            if (success) {
                              AppSnackBars.showSuccess(
                                context,
                                eligible
                                    ? 'Distribution rights granted for this photo.'
                                    : 'Distribution rights revoked for this photo.',
                              );
                            } else {
                              AppSnackBars.showError(context, 'Couldn\'t update distribution rights. Please try again.');
                            }
                          },
                          onReport: (reasonId) async {
                            if (!hasCubit) return;
                            try {
                              await context.read<ForumMediaCubit>().reportMedia(currentMedia, reasonId);
                              if (!context.mounted) return;
                              if (reasonId == 'likeness_no_consent') {
                                Navigator.pop(context);
                                AppSnackBars.showSuccess(
                                  context,
                                  'Photo reported and hidden pending review.',
                                );
                              } else {
                                AppSnackBars.showSuccess(context, 'Media reported.');
                              }
                            } catch (_) {
                              if (context.mounted) {
                                AppSnackBars.showError(context, 'Failed to submit report. Please try again.');
                              }
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),

              if (canComment && currentMedia != null)
                _buildCommentBox(currentMedia, bottomInset: !(showApprove || showDelete)),

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
                                Future<void> performReject() async {
                                  if (hasCubit) {
                                    final success = await context.read<ForumMediaCubit>().deleteMedia(currentMedia);
                                    if (!context.mounted) return;
                                    if (success) {
                                      Navigator.pop(context);
                                    } else {
                                      AppSnackBars.showError(context, 'Failed to remove media. Please try again.');
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
                                final isDestructiveDelete =
                                    hasCubit && isAuthorized && currentMedia.isApproved;
                                if (isDestructiveDelete) {
                                  showMediaDeleteConfirmation(context, performReject);
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
                                final success = await context.read<ForumMediaCubit>().approveMedia(currentMedia);
                                if (!context.mounted) return;
                                if (success) {
                                  Navigator.pop(context);
                                } else {
                                  AppSnackBars.showError(context, 'Failed to approve media. Please try again.');
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



