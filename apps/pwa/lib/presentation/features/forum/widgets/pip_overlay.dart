import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/screens/live_stream_screen.dart';
import 'package:lynk_x/presentation/features/forum/services/forum_video_stream_service.dart';

/// Floating In-App Picture-in-Picture (PiP) card displayed on the Forum page
/// when a live video stream is minimized.
class PipOverlay extends StatefulWidget {
  final String forumName;
  final String hostName;
  final bool isHost;

  const PipOverlay({
    super.key,
    required this.forumName,
    required this.hostName,
    required this.isHost,
  });

  @override
  State<PipOverlay> createState() => _PipOverlayState();
}

class _PipOverlayState extends State<PipOverlay> {
  final ForumVideoStreamService _videoService = ForumVideoStreamService();

  double? _left;
  double? _top;

  static const double _pipWidth = 144.0;
  static const double _pipHeight = 144.0;
  static const double _bottomAllowance = 96.0;
  static const double _margin = 16.0;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;

    // Initialize position to top-left of chat list area (below category filter / tab bar) if unset
    _left ??= _margin;
    _top ??= topPadding + 220.0;

    return ValueListenableBuilder<bool>(
      valueListenable: _videoService.isMinimizedNotifier,
      builder: (context, isMinimized, child) {
        if (!isMinimized || !_videoService.isLiveNotifier.value) {
          return const SizedBox.shrink();
        }

        return Positioned(
          left: _left,
          top: _top,
          width: _pipWidth,
          height: _pipHeight,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _left = (_left! + details.delta.dx).clamp(
                  _margin,
                  screenSize.width - _pipWidth - _margin,
                );
                _top = (_top! + details.delta.dy).clamp(
                  topPadding + 210.0,
                  screenSize.height - _pipHeight - _bottomAllowance,
                );
              });
            },
            child: Material(
              elevation: 14,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              color: const Color(0xFF161920),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Stack(
                  children: [
                    // 1. Live Stream Video Canvas (Tap anywhere to expand)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _expandStreamScreen,
                        child: Stack(
                          children: [
                            if (kIsWeb)
                              const HtmlElementView(viewType: 'lynk-video-stage-view'),
                            if (!_videoService.isCameraOn)
                              Container(
                                color: const Color(0xFF0F1115),
                                child: Center(
                                  child: Icon(
                                    Icons.videocam_off_rounded,
                                    color: context.accentColor,
                                    size: 36,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // 2. Simple Top-Right Expand Action Button (Native Browser PiP feel)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: InkWell(
                        onTap: _expandStreamScreen,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.open_in_full_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _expandStreamScreen() {
    _videoService.setMinimized(false);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveStreamScreen(
          forumName: widget.forumName.isEmpty ? _videoService.forumName : widget.forumName,
          hostName: widget.hostName.isEmpty ? _videoService.hostName : widget.hostName,
          isHost: widget.isHost,
        ),
      ),
    );
  }
}
