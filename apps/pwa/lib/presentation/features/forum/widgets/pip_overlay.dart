import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/services/stream_service.dart';
import 'package:lynk_x/presentation/features/forum/widgets/stage/animated_soundwave_widget.dart';

/// Floating In-App Picture-in-Picture (PiP) card displayed on the Forum page
/// when a live video stream is minimized. Supports Live Call / Live Chat context switching.
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

  // 16:9 Aspect Ratio dimensions
  static const double _pipWidth = 192.0;
  static const double _pipHeight = 108.0;
  static const double _bottomAllowance = 96.0;
  static const double _margin = 16.0;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;

    // Initialize position to top-left of chat list area if unset
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
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              color: const Color(0xFF161920),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Stack(
                  children: [
                    // 1. Live Stream Video Canvas (Tap anywhere to expand to live call stage)
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
                                    size: 32,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // 2. Speaker Name + Waveform Overlay (Bottom-Left)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.hostName.isNotEmpty ? widget.hostName : 'Host',
                              style: AppTypography.interTight(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 5),
                            AnimatedSoundwaveWidget(
                              isSpeaking: true,
                              getAudioLevel: () => 0.5,
                              barColor: context.accentColor,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 3. Top Action Button: Expand Fullscreen
                    Positioned(
                      top: 6,
                      right: 6,
                      child: InkWell(
                        onTap: _expandStreamScreen,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.open_in_full_rounded,
                            color: Colors.white,
                            size: 12,
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
  }
}
