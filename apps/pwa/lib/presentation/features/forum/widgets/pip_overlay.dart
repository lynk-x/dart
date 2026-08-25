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

  static const double _bottomAllowance = 96.0;
  static const double _margin = 16.0;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;

    _left ??= _margin;
    _top ??= topPadding + 220.0;

    return ValueListenableBuilder<bool>(
      valueListenable: _videoService.isMinimizedNotifier,
      builder: (context, isMinimized, child) {
        if (!isMinimized || !_videoService.isLiveNotifier.value) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<StreamType>(
          valueListenable: _videoService.streamTypeNotifier,
          builder: (context, streamType, _) {
            final isLiveCall = streamType == StreamType.liveCall;

            // Dimensions: Live Call uses a slim strip; Live Stream uses 16:9 widescreen canvas
            final double currentWidth = isLiveCall ? 210.0 : 192.0;
            final double currentHeight = isLiveCall ? 48.0 : 108.0;

            return Positioned(
              left: _left,
              top: _top,
              width: currentWidth,
              height: currentHeight,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _left = (_left! + details.delta.dx).clamp(
                      _margin,
                      screenSize.width - currentWidth - _margin,
                    );
                    _top = (_top! + details.delta.dy).clamp(
                      topPadding + 210.0,
                      screenSize.height - currentHeight - _bottomAllowance,
                    );
                  });
                },
                child: Material(
                  elevation: 14,
                  borderRadius: BorderRadius.circular(isLiveCall ? 24 : 10),
                  clipBehavior: Clip.antiAlias,
                  color: const Color(0xFF161920),
                  child: isLiveCall
                      ? _buildLiveCallStrip(context)
                      : _buildLiveStreamContainer(context),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Compact Audio Strip for Live Calls (No video canvas, no mic indicator, tap does nothing)
  Widget _buildLiveCallStrip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF12141A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.accentColor.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.hostName.isNotEmpty ? widget.hostName : 'Host',
              style: AppTypography.interTight(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          AnimatedSoundwaveWidget(
            isSpeaking: true,
            getAudioLevel: () => 0.5,
            barColor: context.accentColor,
          ),
        ],
      ),
    );
  }

  /// 16:9 Video Broadcast Container for Live Streams (Tap reverts/expands stream stage)
  Widget _buildLiveStreamContainer(BuildContext context) {
    return GestureDetector(
      onTap: () => _videoService.setMinimized(false),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Stack(
          children: [
            // 1. Video Canvas Preview
            Positioned.fill(
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

            // 2. Host Name & Soundwave
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

            // 3. Top-Right Expand Icon (Explicit Revert Action)
            Positioned(
              top: 6,
              right: 6,
              child: InkWell(
                onTap: () => _videoService.setMinimized(false),
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
    );
  }
}
