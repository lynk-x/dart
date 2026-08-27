import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_audio_stream_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_audio_stream_state.dart';
import 'package:lynk_x/presentation/features/forum/services/audio_telemetry_service.dart';
import 'package:lynk_x/presentation/features/forum/services/pip_service.dart';
import 'package:lynk_x/presentation/features/forum/services/stream_service.dart';
import 'package:lynk_x/presentation/features/forum/widgets/forum_header.dart';
import 'package:lynk_x/presentation/features/forum/widgets/stage/soundwave_widget.dart';

/// Floating In-App Picture-in-Picture (PiP) card displayed on the Forum page
/// when a live video stream or audio call is minimized. Supports Live Call / Live Chat context switching.
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
  final StreamPipService _pipService = StreamPipService();
  final ForumVideoStreamService _videoService = ForumVideoStreamService();
  final AudioTelemetryService _telemetry = AudioTelemetryService();

  double? _left;
  double? _top;

  static const double _bottomAllowance = 96.0;
  static const double _margin = 16.0;

  @override
  void initState() {
    super.initState();
    // Start shared polling timer — ref-counted, safe to call multiple times.
    _telemetry.startPolling();
  }

  @override
  void dispose() {
    _telemetry.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;

    _left ??= _margin;
    _top ??= topPadding + 220.0;

    return ValueListenableBuilder<bool>(
      valueListenable: _pipService.isMinimizedNotifier,
      builder: (context, isMinimized, child) {
        if (!isMinimized || !_pipService.isLiveNotifier.value) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<PipStreamType>(
          valueListenable: _pipService.streamTypeNotifier,
          builder: (context, streamType, _) {
            final isLiveCall = streamType == PipStreamType.liveCall;

            // Dimensions: Live Call uses a slim strip; Live Stream uses 16:9 widescreen canvas
            final double currentWidth = isLiveCall ? 230.0 : 192.0;
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

  /// Compact Audio Strip for Live Calls with Mic Toggle
  Widget _buildLiveCallStrip(BuildContext context) {
    final audioCubit = context.read<ForumAudioStreamCubit?>();
    final cubit = audioCubit;

    if (cubit == null) {
      return _buildRawCallStrip(
        context,
        isMicMuted: true,
        canSpeak: widget.isHost,
        onToggleMic: null,
      );
    }

    return BlocBuilder<ForumAudioStreamCubit, ForumAudioStreamState>(
      bloc: cubit,
      builder: (context, audioState) {
        final canSpeak = widget.isHost ||
            audioState.role == ForumHeaderRole.host ||
            audioState.role == ForumHeaderRole.speaker ||
            audioState.isLive;

        return _buildRawCallStrip(
          context,
          isMicMuted: audioState.isMicMuted,
          canSpeak: canSpeak,
          onToggleMic: () async {
            await cubit.toggleMic();
          },
        );
      },
    );
  }

  Widget _buildRawCallStrip(
    BuildContext context, {
    required bool isMicMuted,
    required bool canSpeak,
    required VoidCallback? onToggleMic,
  }) {
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
          SoundwaveWidget(
            isSpeaking: !isMicMuted,
            audioLevelNotifier: _telemetry.levelNotifier,
            barColor: context.accentColor,
          ),
          if (canSpeak) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onToggleMic,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: isMicMuted
                      ? Colors.red.withValues(alpha: 0.25)
                      : context.accentColor.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  size: 16,
                  color: isMicMuted ? Colors.redAccent : context.accentColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 16:9 Video Broadcast Container for Live Streams with bottom-right mic & camera controls
  Widget _buildLiveStreamContainer(BuildContext context) {
    void expandStream() {
      _pipService.setMinimized(false);
      _videoService.setMinimized(false);
    }

    return GestureDetector(
      onTap: expandStream,
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

            // 2. Host Name & Soundwave (Bottom Left)
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
                    SoundwaveWidget(
                      isSpeaking: true,
                      audioLevelNotifier: _telemetry.levelNotifier,
                      barColor: context.accentColor,
                    ),
                  ],
                ),
              ),
            ),

            // 3. Bottom-Right Video & Mic Toggle Icons
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {
                        final nextMic = !_videoService.isMicMuted;
                        _videoService.isMicMuted = nextMic;
                        _videoService.toggleMic(!nextMic);
                        setState(() {});
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          _videoService.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          size: 14,
                          color: _videoService.isMicMuted ? Colors.redAccent : context.accentColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    InkWell(
                      onTap: () {
                        final nextCam = !_videoService.isCameraOn;
                        _videoService.isCameraOn = nextCam;
                        _videoService.toggleCamera(nextCam);
                        setState(() {});
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          _videoService.isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                          size: 14,
                          color: _videoService.isCameraOn ? context.accentColor : Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 4. Top-Right Expand Icon
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
