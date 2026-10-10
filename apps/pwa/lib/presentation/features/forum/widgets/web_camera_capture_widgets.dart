import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:video_player/video_player.dart';

/// One file picked via the gallery shortcut, pending review. Identity
/// (`==`) is the default object identity — fine here since each pick
/// produces distinct PlatformFile instances even for same-named files.
class PickedMediaItem {
  final XFile file;
  final Uint8List bytes;

  PickedMediaItem({required this.file, required this.bytes});

  bool get isVideo {
    final ext = file.name.split('.').last.toLowerCase();
    return _videoExtensions.contains(ext);
  }
}

/// Grid review shown after a gallery pick, before the files are handed
/// back to the caller — mirrors [CaptureReview]'s "don't upload until
/// confirmed" principle, but as a grid (with per-item removal) rather than
/// single-item Retake/Use, since FileType.media allows multi-select and
/// mixed image/video types in one pick.
class GalleryReview extends StatelessWidget {
  final List<PickedMediaItem> items;
  final ValueChanged<PickedMediaItem> onRemove;
  final VoidCallback onCancel;
  final VoidCallback onUse;

  const GalleryReview({super.key, 
    required this.items,
    required this.onRemove,
    required this.onCancel,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${items.length} selected',
                    style: AppTypography.interTight(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  RoundIconButton(icon: Icons.close, onTap: onCancel),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'No items left — cancel to go back to the camera.',
                        textAlign: TextAlign.center,
                        style: AppTypography.inter(fontSize: 13, color: Colors.white54),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return GalleryReviewTile(
                          item: item,
                          onRemove: () => onRemove(item),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: PrimaryButton(
                icon: Icons.check_circle_outline,
                text: items.isEmpty
                    ? 'Use Selected'
                    : 'Use ${items.length} ${items.length == 1 ? 'item' : 'items'}',
                backgroundColor: context.accentColor,
                textColor: Colors.black,
                onPressed: items.isEmpty ? null : onUse,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GalleryReviewTile extends StatelessWidget {
  final PickedMediaItem item;
  final VoidCallback onRemove;

  const GalleryReviewTile({super.key, required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.isVideo)
            Container(
              color: Colors.grey[900],
              child: const Center(
                child: Icon(Icons.play_circle_fill, color: Colors.white38, size: 32),
              ),
            )
          else
            Image.memory(item.bytes, fit: BoxFit.cover),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen review shown after capture, before the result is handed back
/// to the caller — lets a bad take (blocked framing, motion blur, wrong
/// mode) be discarded and retaken instead of only being catchable after
/// upload via delete/report.
class CaptureReview extends StatefulWidget {
  final WebCameraCaptureResult result;
  final VideoPlayerController? videoController;
  final VoidCallback onRetake;
  final Function(bool isMuted) onUse;

  const CaptureReview({super.key, 
    required this.result,
    required this.videoController,
    required this.onRetake,
    required this.onUse,
  });

  @override
  State<CaptureReview> createState() => _CaptureReviewState();
}

class _CaptureReviewState extends State<CaptureReview> {
  late bool _isMuted;

  @override
  void initState() {
    super.initState();
    _isMuted = widget.videoController?.value.volume == 0.0;
  }

  void _toggleMute() {
    if (widget.videoController == null) return;
    setState(() {
      _isMuted = !_isMuted;
      widget.videoController!.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: widget.result.isVideo
                ? (widget.videoController != null && widget.videoController!.value.isInitialized
                    ? GestureDetector(
                        onTap: () {
                          if (widget.videoController!.value.isPlaying) {
                            widget.videoController!.pause();
                          } else {
                            widget.videoController!.play();
                          }
                        },
                        child: SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: widget.videoController!.value.size.width > 0
                                  ? widget.videoController!.value.size.width
                                  : 1280,
                              height: widget.videoController!.value.size.height > 0
                                  ? widget.videoController!.value.size.height
                                  : 720,
                              child: VideoPlayer(widget.videoController!),
                            ),
                          ),
                        ),
                      )
                    : CircularProgressIndicator(color: context.accentColor))
                : SizedBox.expand(
                    child: Image.network(widget.result.objectUrl, fit: BoxFit.cover),
                  ),
          ),
          if (widget.result.isVideo && widget.videoController != null)
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: GestureDetector(
                  onTap: _toggleMute,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          color: _isMuted ? Colors.redAccent : context.accentColor,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isMuted ? 'Muted' : 'Audio On',
                          style: AppTypography.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.replay, size: 20),
                          label: Text(
                            'Retake',
                            style: AppTypography.interTight(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: widget.onRetake,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: PrimaryButton(
                        icon: Icons.check_circle_outline,
                        text: widget.result.isVideo ? 'Use Video' : 'Use Photo',
                        backgroundColor: context.accentColor,
                        textColor: Colors.black,
                        onPressed: () => widget.onUse(_isMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ModeToggle extends StatelessWidget {
  final bool isVideoMode;
  final ValueChanged<bool> onChanged;
  final Color accentColor;

  const ModeToggle({super.key, 
    required this.isVideoMode,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ModeOption(
            label: 'Photo',
            active: !isVideoMode,
            activeColor: accentColor,
            activeTextColor: Colors.black,
            onTap: () => onChanged(false),
          ),
          ModeOption(
            label: 'Video',
            active: isVideoMode,
            activeColor: Colors.redAccent,
            activeTextColor: Colors.white,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class ModeOption extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final Color activeTextColor;
  final VoidCallback onTap;

  const ModeOption({super.key, 
    required this.label,
    required this.active,
    required this.activeColor,
    required this.activeTextColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: AppTypography.inter(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: active ? activeTextColor : Colors.white54,
          ),
        ),
      ),
    );
  }
}

class ShutterButton extends StatelessWidget {
  final bool isVideoMode;
  final bool isRecording;
  final double? recordProgress;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ShutterButton({super.key, 
    required this.isVideoMode,
    required this.isRecording,
    this.recordProgress,
    required this.isBusy,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    const double outerSize = 68.0;
    const double strokeWidth = 4.0;

    return GestureDetector(
      onTap: isBusy ? null : onTap,
      onLongPress: isBusy ? null : onLongPress,
      child: SizedBox(
        width: outerSize,
        height: outerSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isRecording && recordProgress != null)
              SizedBox.expand(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: recordProgress!),
                  duration: const Duration(milliseconds: 100),
                  curve: Curves.linear,
                  builder: (context, animatedProgress, child) {
                    return CircularProgressIndicator(
                      value: animatedProgress,
                      strokeWidth: strokeWidth,
                      color: Colors.redAccent,
                      backgroundColor: Colors.white,
                    );
                  },
                ),
              )
            else
              Container(
                width: outerSize,
                height: outerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: strokeWidth),
                ),
              ),
            Center(
              child: isBusy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: isVideoMode && isRecording ? 24 : 52,
                      height: isVideoMode && isRecording ? 24 : 52,
                      decoration: BoxDecoration(
                        color: isVideoMode ? Colors.redAccent : Colors.white,
                        borderRadius: BorderRadius.circular(
                          isVideoMode && isRecording ? 6 : 26,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class GalleryShortcutButton extends StatelessWidget {
  final VoidCallback? onTap;

  const GalleryShortcutButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Icon(
          Icons.photo_library_outlined,
          color: onTap == null ? Colors.white24 : Colors.white70,
          size: 26,
        ),
      ),
    );
  }
}

class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? iconColor;

  const RoundIconButton({super.key, required this.icon, required this.onTap, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.4),
        ),
        child: Icon(
          icon,
          color: onTap == null ? Colors.white24 : (iconColor ?? Colors.white),
          size: 24,
        ),
      ),
    );
  }
}

class WebCameraCaptureResult {
  final String objectUrl;
  final bool isVideo;
  final bool isMuted;
  /// Non-empty when the user picked existing files via the in-screen
  /// gallery shortcut instead of capturing — objectUrl/isVideo are unused
  /// placeholders in that case. media_tab.dart checks this and uploads
  /// these directly through the same path as a normal gallery pick.
  final List<XFile> pickedFiles;

  const WebCameraCaptureResult({
    required this.objectUrl,
    required this.isVideo,
    this.isMuted = false,
  }) : pickedFiles = const [];

  const WebCameraCaptureResult.pickedFiles(this.pickedFiles)
      : objectUrl = '',
        isVideo = false,
        isMuted = false;
}

const _videoExtensions = {
  'mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi', '3gp',
};
