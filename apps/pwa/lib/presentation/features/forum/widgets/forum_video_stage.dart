import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:web/web.dart' as web;

import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import '../services/forum_video_stream_service.dart';
import 'bottom_dock.dart';
import 'forum_header.dart';
import 'speaker_tag.dart';

/// Interactive Forum Video Stage featuring actual Web Camera capture,
/// hardware mic control, browser Picture-in-Picture (PiP), and refined stage controls.
class ForumVideoStage extends StatefulWidget {
  final String forumName;
  final String hostName;
  final bool isHost;

  const ForumVideoStage({
    super.key,
    this.forumName = 'Community Live Stream',
    this.hostName = 'Alex',
    this.isHost = true,
  });

  @override
  State<ForumVideoStage> createState() => _ForumVideoStageState();
}

class _ForumVideoStageState extends State<ForumVideoStage> with WidgetsBindingObserver {
  final ForumVideoStreamService _videoService = ForumVideoStreamService();

  static const String _elementId = 'lynk_live_video_stage';
  static const String _viewType = 'lynk-video-stage-view';
  static bool _viewRegistered = false;

  web.HTMLVideoElement? _videoElement;
  bool _isMicMuted = false;
  bool _isCameraOn = true;
  bool _isFrontCamera = true;
  bool _showTelemetryOverlay = false;
  bool _showLiveChatOverlay = true;
  int _sessionDurationSeconds = 0;

  final List<Map<String, dynamic>> _unifiedStreamMessages = const [
    {
      'id': 'm1',
      'type': 'chat',
      'sender': 'Marcus',
      'role': 'VIP',
      'text': 'Great video clarity today! 🔥',
    },
    {
      'id': 'm2',
      'type': 'announcement',
      'sender': 'Alex (Host)',
      'role': 'Organizer',
      'text': 'Welcome everyone! Taking Q&A right after the deck presentation.',
    },
    {
      'id': 'm3',
      'type': 'chat',
      'sender': 'Sarah_K',
      'role': 'Speaker',
      'text': 'Excited for the live feature announcement!',
    },
    {
      'id': 'm4',
      'type': 'chat',
      'sender': 'David_Dev',
      'role': 'Spectator',
      'text': 'Can we ask questions about offline sync capability?',
    },
  ];

  Timer? _spectatorTimer;
  Timer? _audioLevelTimer;
  Timer? _durationTimer;
  Timer? _telemetryTimer;
  double _currentAudioLevel = 0.0;
  JSFunction? _onScreenShareEndedListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      _onScreenShareEndedListener = (web.Event event) {
        if (mounted && _isScreenSharing) {
          setState(() {
            _isScreenSharing = false;
          });
        }
      }.toJS;
      web.window.addEventListener('lynkScreenShareEnded', _onScreenShareEndedListener);

      if (!_viewRegistered) {
        _videoElement = web.HTMLVideoElement()
          ..id = _elementId
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover';
        _videoElement!.setAttribute('playsinline', 'true');
        _videoElement!.setAttribute('autoplay', 'true');
        _videoElement!.setAttribute('muted', 'true');
        _videoElement!.muted = true;

        ui_web.platformViewRegistry.registerViewFactory(
          _viewType,
          (int viewId) => _videoElement!,
        );
        _viewRegistered = true;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCameraAndAudio();
    });

    _startSpectatorSimulation();
    _startAudioLevelPolling();
    _startDurationTimer();
    _startTelemetryPolling();
  }

  void _startTelemetryPolling() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _videoService.fetchTelemetryStats();
    });
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _sessionDurationSeconds++;
      });
    });
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    final hours = totalSeconds ~/ 3600;
    if (hours > 0) {
      final h = hours.toString().padLeft(2, '0');
      return '$h:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _videoService.releaseWakeLock();
    } else if (state == AppLifecycleState.resumed) {
      _videoService.requestWakeLock();
    }
  }

  Future<void> _initCameraAndAudio() async {
    _videoService.requestWakeLock();
    _videoService.setLive(true);
    _videoService.forumName = widget.forumName;
    _videoService.hostName = widget.hostName;
    _videoService.isHost = widget.isHost;

    if (widget.hostName.isNotEmpty) {
      _videoService.updateHostSpeakerName(
        widget.hostName,
        role: widget.isHost ? 'Host' : 'Speaker',
        isHostUser: widget.isHost,
      );
    }

    if (_videoElement != null) {
      _videoElement!.style.transform = _isFrontCamera ? 'scaleX(-1)' : 'none';
    }

    if (!_videoService.isMinimizedNotifier.value) {
      final success = await _videoService.startVideoStream(_elementId, isFrontCamera: _isFrontCamera);
      if (mounted && !success) {
        AppSnackBars.showInfo(context, 'Camera permission requested or offline preview active');
      }
    } else {
      _videoService.setMinimized(false);
    }
  }

  void _startSpectatorSimulation() {
    _spectatorTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() {
        _videoService.spectatorCount += (1 - (DateTime.now().second % 3));
      });
    });
  }

  void _startAudioLevelPolling() {
    _audioLevelTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      if (_isMicMuted) {
        if (_currentAudioLevel != 0.0) {
          setState(() {
            _currentAudioLevel = 0.0;
          });
        }
        return;
      }
      final level = _videoService.getAudioLevel();
      if ((level - _currentAudioLevel).abs() > 0.05) {
        setState(() {
          _currentAudioLevel = level;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (kIsWeb && _onScreenShareEndedListener != null) {
      web.window.removeEventListener('lynkScreenShareEnded', _onScreenShareEndedListener);
    }
    _spectatorTimer?.cancel();
    _audioLevelTimer?.cancel();
    _durationTimer?.cancel();
    _telemetryTimer?.cancel();
    if (!_videoService.isMinimizedNotifier.value) {
      _videoService.releaseWakeLock();
      _videoService.stopVideoStream();
    }
    super.dispose();
  }

  bool _isScreenSharing = false;

  Future<void> _toggleScreenShare() async {
    if (_isScreenSharing) {
      await _videoService.startVideoStream(_elementId, isFrontCamera: _isFrontCamera);
      setState(() {
        _isScreenSharing = false;
      });
    } else {
      final success = await _videoService.startScreenShare(_elementId);
      if (success) {
        setState(() {
          _isScreenSharing = true;
        });
      } else if (mounted) {
        AppSnackBars.showInfo(context, 'Screen share cancelled or restricted on this mobile browser. Try Desktop or Chrome Android.');
      }
    }
  }

  void _toggleMic() {
    final nextMuted = !_isMicMuted;
    setState(() {
      _isMicMuted = nextMuted;
    });
    _videoService.toggleMic(!nextMuted);
    _videoService.updateParticipantMediaState('host', isMicMuted: nextMuted);
  }

  void _toggleCamera() {
    final nextCameraOn = !_isCameraOn;
    setState(() {
      _isCameraOn = nextCameraOn;
    });
    _videoService.isCameraOn = nextCameraOn;
    _videoService.toggleCamera(nextCameraOn);
    _videoService.updateParticipantMediaState('host', isCameraOn: nextCameraOn);
  }

  Future<void> _flipCamera() async {
    final nextFront = !_isFrontCamera;
    setState(() {
      _isFrontCamera = nextFront;
    });
    _videoService.isFrontCamera = nextFront;
    if (_videoElement != null) {
      _videoElement!.style.transform = nextFront ? 'scaleX(-1)' : 'none';
    }
    _videoService.setCameraMirror(nextFront);
    await _videoService.startVideoStream(_elementId, isFrontCamera: nextFront);
    _videoService.toggleMic(!_isMicMuted);
    _videoService.toggleCamera(_isCameraOn);
  }

  Future<void> _triggerPictureInPicture() async {
    _videoService.setMinimized(true);
    if (mounted) {
      AppSnackBars.showInfo(context, 'Minimizing live stage');
    }
  }

  void _showTelemetryDetailsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121418),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return ValueListenableBuilder<TelemetryData>(
          valueListenable: _videoService.telemetryNotifier,
          builder: (context, telemetry, _) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.analytics_rounded, color: context.accentColor, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Stream Diagnostics & Telemetry',
                        style: AppTypography.interTight(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTelemetryRow('Session Uptime', _formatDuration(_sessionDurationSeconds), Icons.timer_outlined),
                  _buildTelemetryRow('Network Latency', '${telemetry.rttMs} ms (RTT Edge)', Icons.speed_rounded),
                  _buildTelemetryRow('Video Resolution', '${telemetry.height}p (${telemetry.width}x${telemetry.height} @ ${telemetry.fps} FPS)', Icons.hd_rounded),
                  _buildTelemetryRow('Video Bitrate', '${telemetry.bitrateMbps} Mbps (${telemetry.codec})', Icons.graphic_eq_rounded),
                  _buildTelemetryRow('Audio Bitrate', '128 kbps (Opus 48kHz Stereo)', Icons.mic_outlined),
                  _buildTelemetryRow('Packet Loss', '${telemetry.packetLossPercent}%', Icons.network_check_rounded),
                  _buildTelemetryRow('Stream Security', 'DTLS-SRTP (End-to-End Encrypted)', Icons.lock_outline_rounded),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTelemetryRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 16),
          const SizedBox(width: 10),
          Text(
            label,
            style: AppTypography.interTight(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: AppTypography.interTight(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridStageOverlay(BuildContext context) {
    final participants = _videoService.activeParticipantsNotifier.value;
    final count = participants.length.clamp(1, 4);

    return Container(
      color: const Color(0xFF0C0E12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final availableHeight = constraints.maxHeight;

          const double padding = 8.0;
          const double spacing = 8.0;

          int crossAxisCount = 2;
          if (count == 1) {
            crossAxisCount = 1;
          }

          final int rowCount = (count / crossAxisCount).ceil();
          final double totalSpacingX = (crossAxisCount - 1) * spacing + (padding * 2);
          final double totalSpacingY = (rowCount - 1) * spacing + (padding * 2);

          final double tileWidth = (availableWidth - totalSpacingX) / crossAxisCount;
          final double tileHeight = (availableHeight - totalSpacingY) / rowCount;
          final double childAspectRatio = (tileWidth > 0 && tileHeight > 0)
              ? tileWidth / tileHeight
              : 1.0;

          return Padding(
            padding: const EdgeInsets.all(padding),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: childAspectRatio,
              ),
              itemCount: count,
              itemBuilder: (context, index) {
                final p = participants[index];
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF161920),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: p.isSpeaking ? context.accentColor : Colors.white12,
                      width: p.isSpeaking ? 2 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: p.isSpeaking ? context.accentColor : const Color(0xFF2A2E38),
                          child: Text(
                            p.name.isNotEmpty ? p.name.substring(0, 1).toUpperCase() : '?',
                            style: AppTypography.interTight(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            p.name,
                            style: AppTypography.interTight(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: p.isSpeaking
                                  ? context.accentColor.withValues(alpha: 0.5)
                                  : Colors.white12,
                            ),
                          ),
                          child: AnimatedSoundwaveWidget(
                            isSpeaking: p.isSpeaking,
                            getAudioLevel: () => _currentAudioLevel,
                            barColor: p.isSpeaking ? context.accentColor : Colors.white54,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildPresentationStageOverlay(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0C10),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF131722),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.indigoAccent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.present_to_all_rounded, size: 42, color: Colors.indigoAccent),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Shared Presentation Stage',
                      style: AppTypography.interTight(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Screen share or slides deck actively broadcasting',
                      style: AppTypography.interTight(fontSize: 12, color: Colors.white38),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mainStageArea = Expanded(
      child: Stack(
        children: [
          // VIDEO CANVAS STAGE
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: _flipCamera,
              behavior: HitTestBehavior.opaque,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF0F1115),
                ),
                child: ValueListenableBuilder<StageLayoutMode>(
                  valueListenable: _videoService.stageLayoutNotifier,
                  builder: (context, layoutMode, _) {
                    if (layoutMode == StageLayoutMode.grid) {
                      return _buildGridStageOverlay(context);
                    }
                    if (layoutMode == StageLayoutMode.presentation) {
                      return _buildPresentationStageOverlay(context);
                    }

                    return Stack(
                      children: [
                        // Actual Web Video Stream PlatformView
                        if (kIsWeb)
                          const Positioned.fill(
                            child: HtmlElementView(viewType: _viewType),
                          ),

                        // Camera Off Overlay Placeholder
                        if (!_isCameraOn && !_isScreenSharing)
                          Positioned.fill(
                            child: Container(
                              color: const Color(0xFF0F1115),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: 36,
                                      backgroundColor: const Color(0xFF1E222B),
                                      child: Text(
                                        widget.hostName.isNotEmpty
                                            ? widget.hostName.substring(0, 1).toUpperCase()
                                            : 'L',
                                        style: AppTypography.interTight(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      widget.hostName,
                                      style: AppTypography.interTight(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Camera Off',
                                      style: AppTypography.interTight(
                                        fontSize: 12,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 16,
            right: 16,
            child: ValueListenableBuilder<List<StreamParticipant>>(
              valueListenable: _videoService.activeParticipantsNotifier,
              builder: (context, participants, _) {
                final activeParticipant = participants.firstWhere(
                  (p) => p.isHost,
                  orElse: () => StreamParticipant(
                    id: 'host',
                    name: widget.hostName,
                    role: widget.isHost ? 'Host' : 'Speaker',
                    isSpeaking: !_isMicMuted,
                  ),
                );
                return SpeakerTag(
                  activeParticipant: activeParticipant,
                  audioLevel: _currentAudioLevel,
                );
              },
            ),
          ),

          // STAGE MODE SELECTOR OVERLAY (Bottom Left)
          Positioned(
            bottom: 16,
            left: 16,
            child: ValueListenableBuilder<StageLayoutMode>(
              valueListenable: _videoService.stageLayoutNotifier,
              builder: (context, layoutMode, _) {
                return Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => _videoService.setStageLayout(StageLayoutMode.focus),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: layoutMode == StageLayoutMode.focus ? context.accentColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.person_rounded,
                                size: 14,
                                color: layoutMode == StageLayoutMode.focus ? Colors.black : Colors.white60,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Focus',
                                style: AppTypography.interTight(
                                  fontSize: 11,
                                  color: layoutMode == StageLayoutMode.focus ? Colors.black : Colors.white60,
                                  fontWeight: layoutMode == StageLayoutMode.focus ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      InkWell(
                        onTap: () => _videoService.setStageLayout(StageLayoutMode.grid),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: layoutMode == StageLayoutMode.grid ? context.accentColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.grid_view_rounded,
                                size: 14,
                                color: layoutMode == StageLayoutMode.grid ? Colors.black : Colors.white60,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Grid',
                                style: AppTypography.interTight(
                                  fontSize: 11,
                                  color: layoutMode == StageLayoutMode.grid ? Colors.black : Colors.white60,
                                  fontWeight: layoutMode == StageLayoutMode.grid ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      InkWell(
                        onTap: () => _videoService.setStageLayout(StageLayoutMode.presentation),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: layoutMode == StageLayoutMode.presentation ? context.accentColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.present_to_all_rounded,
                                size: 14,
                                color: layoutMode == StageLayoutMode.presentation ? Colors.black : Colors.white60,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Deck',
                                style: AppTypography.interTight(
                                  fontSize: 11,
                                  color: layoutMode == StageLayoutMode.presentation ? Colors.black : Colors.white60,
                                  fontWeight: layoutMode == StageLayoutMode.presentation ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _showLiveChatOverlay = !_showLiveChatOverlay;
                          });
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: _showLiveChatOverlay
                                ? context.accentColor.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            _showLiveChatOverlay
                                ? Icons.chat_bubble_rounded
                                : Icons.chat_bubble_outline_rounded,
                            size: 14,
                            color: _showLiveChatOverlay
                                ? context.accentColor
                                : Colors.white60,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // UNIFIED LIVE CHAT STREAM SLIVERLIST OVERLAY
          if (_showLiveChatOverlay)
            Positioned(
              bottom: 60,
              left: 16,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (MediaQuery.of(context).size.width * 0.7).clamp(200, 320),
                  maxHeight: 160,
                ),
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black, Colors.black],
                      stops: [0.0, 0.2, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: CustomScrollView(
                    reverse: true,
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final msg = _unifiedStreamMessages[index];
                            final isAnnouncement = msg['type'] == 'announcement';
                            final sender = (msg['sender'] ?? 'User').toString();
                            final text = (msg['text'] ?? '').toString();
                            final role = (msg['role'] ?? 'Spectator').toString();

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isAnnouncement
                                      ? context.accentColor.withValues(alpha: 0.25)
                                      : Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isAnnouncement
                                        ? context.accentColor.withValues(alpha: 0.6)
                                        : Colors.white12,
                                    width: isAnnouncement ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isAnnouncement) ...[
                                          Icon(Icons.campaign_rounded, size: 12, color: context.accentColor),
                                          const SizedBox(width: 4),
                                          Text(
                                            'ANNOUNCEMENT',
                                            style: AppTypography.interTight(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: context.accentColor,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Text(
                                          sender,
                                          style: AppTypography.interTight(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        if (role.isNotEmpty) ...[
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: isAnnouncement
                                                  ? context.accentColor
                                                  : Colors.white24,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              role.toUpperCase(),
                                              style: AppTypography.inter(
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                                color: isAnnouncement ? Colors.black : Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      text,
                                      style: AppTypography.interTight(
                                        fontSize: 11,
                                        color: Colors.white.withValues(alpha: 0.95),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: _unifiedStreamMessages.length,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // STREAM TELEMETRY OVERLAY
          if (_showTelemetryOverlay)
            Positioned(
              top: 56,
              left: 16,
              child: GestureDetector(
                onTap: _showTelemetryDetailsModal,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: ValueListenableBuilder<TelemetryData>(
                    valueListenable: _videoService.telemetryNotifier,
                    builder: (context, telemetry, _) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.white38, size: 12),
                          const SizedBox(width: 6),
                          Text(
                            '${telemetry.summaryLabel} • Uptime ${_formatDuration(_sessionDurationSeconds)}',
                            style: AppTypography.interTight(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),

          // TOP BAR OVERLAY
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Left: Minimize / Browser PiP Trigger
                InkWell(
                  onTap: _triggerPictureInPicture,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Icon(
                      Icons.picture_in_picture_alt_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),

                // Top Right: Telemetry Toggle + Combined LIVE & Spectator Count Badge
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Telemetry Toggle Button
                    IconButton(
                      icon: Icon(
                        _showTelemetryOverlay
                            ? Icons.analytics_rounded
                            : Icons.analytics_outlined,
                        color: _showTelemetryOverlay
                            ? context.accentColor
                            : Colors.white70,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _showTelemetryOverlay = !_showTelemetryOverlay;
                        });
                      },
                      tooltip: 'Toggle Stream Telemetry',
                    ),
                    const SizedBox(width: 4),

                    // Combined LIVE & Spectator Count Badge
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'LIVE',
                              style: AppTypography.interTight(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.remove_red_eye_rounded,
                              color: Colors.white70, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${_videoService.spectatorCount}',
                            style: AppTypography.interTight(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final bottomDock = BottomDock(
      isDisabled: !widget.isHost,
      isScreenSharing: _isScreenSharing,
      isMicMuted: _isMicMuted,
      isCameraOn: _isCameraOn,
      isFrontCamera: _isFrontCamera,
      isLeaveRoom: !widget.isHost,
      onToggleScreenShare: _toggleScreenShare,
      onToggleMic: _toggleMic,
      onToggleCamera: _toggleCamera,
      onFlipCamera: _flipCamera,
      onEndCall: () {
        _videoService.setMinimized(false);
        _videoService.stopVideoStream();
        _videoService.setLive(false);
      },
    );

    return Container(
      color: const Color(0xFF0F1115),
      child: Column(
        children: [
          mainStageArea,
          bottomDock,
        ],
      ),
    );
  }
}
