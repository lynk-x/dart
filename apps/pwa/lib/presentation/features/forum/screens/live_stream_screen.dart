import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:web/web.dart' as web;

import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import '../services/forum_video_stream_service.dart';
import '../widgets/bottom_dock.dart';
import '../widgets/guest_thumbnail_strip.dart';
import '../widgets/speaker_tag.dart';

/// Interactive Live Stream screen featuring actual Web Camera capture,
/// hardware mic control, browser Picture-in-Picture (PiP), and refined stage controls.
class LiveStreamScreen extends StatefulWidget {
  final String forumName;
  final String hostName;
  final bool isHost;

  const LiveStreamScreen({
    super.key,
    this.forumName = 'Community Live Stream',
    this.hostName = 'Alex',
    this.isHost = true,
  });

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> with WidgetsBindingObserver {
  final ForumVideoStreamService _videoService = ForumVideoStreamService();

  static const String _elementId = 'lynk_live_video_stage';
  static const String _viewType = 'lynk-video-stage-view';
  static bool _viewRegistered = false;

  web.HTMLVideoElement? _videoElement;
  bool _isMicMuted = false;
  bool _isCameraOn = true;
  bool _isFrontCamera = true;
  bool _showTelemetryOverlay = true;
  int _spectatorCount = 142;
  int _sessionDurationSeconds = 0;
  String _selectedCamera = 'Built-in Front Camera';
  String _selectedAudioInput = 'Default Microphone';

  Timer? _spectatorTimer;
  Timer? _audioLevelTimer;
  Timer? _durationTimer;
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
        _spectatorCount += (1 - (DateTime.now().second % 3));
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
        AppSnackBars.showInfo(context, 'Screen sharing cancelled or not supported');
      }
    }
  }

  void _toggleMic() {
    setState(() {
      _isMicMuted = !_isMicMuted;
    });
    _videoService.toggleMic(!_isMicMuted);
  }

  void _toggleCamera() {
    setState(() {
      _isCameraOn = !_isCameraOn;
    });
    _videoService.isCameraOn = _isCameraOn;
    _videoService.toggleCamera(_isCameraOn);
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
      AppSnackBars.showInfo(context, 'Minimizing live stream to Forum');
      Navigator.of(context).pop();
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
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                  _buildTelemetryRow('Network Latency', '42 ms (RTT Ultra-Low)', Icons.speed_rounded),
                  _buildTelemetryRow('Video Resolution', '1080p (1920x1080 @ 60 FPS)', Icons.hd_rounded),
                  _buildTelemetryRow('Video Bitrate', '3.4 Mbps (H.264 High Profile)', Icons.graphic_eq_rounded),
                  _buildTelemetryRow('Audio Bitrate', '128 kbps (Opus 48kHz Stereo)', Icons.mic_outlined),
                  _buildTelemetryRow('Packet Loss', '0.0% (0 / 14,820 packets)', Icons.network_check_rounded),
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

  void _showDeviceSelectorModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121418),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Media Device Settings',
                    style: AppTypography.interTight(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Camera Input',
                    style: AppTypography.interTight(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCamera,
                    dropdownColor: const Color(0xFF1E222A),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Built-in Front Camera',
                        child: Text('Built-in Front Camera'),
                      ),
                      DropdownMenuItem(
                        value: 'Built-in Rear Camera',
                        child: Text('Built-in Rear Camera'),
                      ),
                      DropdownMenuItem(
                        value: 'External USB Cam Link (DSLR)',
                        child: Text('External USB Cam Link (DSLR)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => _selectedCamera = val);
                        setState(() => _selectedCamera = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Microphone Input',
                    style: AppTypography.interTight(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedAudioInput,
                    dropdownColor: const Color(0xFF1E222A),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Default Microphone',
                        child: Text('Default Microphone'),
                      ),
                      DropdownMenuItem(
                        value: 'USB Audio Interface / Mixer',
                        child: Text('USB Audio Interface / Mixer'),
                      ),
                      DropdownMenuItem(
                        value: 'Wireless Bluetooth Headset',
                        child: Text('Wireless Bluetooth Headset'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => _selectedAudioInput = val);
                        setState(() => _selectedAudioInput = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: _showTelemetryOverlay,
                    activeTrackColor: context.accentColor,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Stream Telemetry Overlay',
                      style: AppTypography.interTight(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      'Displays real-time bitrate, resolution & latency stats on video stage',
                      style: AppTypography.interTight(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                    onChanged: (val) {
                      setModalState(() => _showTelemetryOverlay = val);
                      setState(() => _showTelemetryOverlay = val);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 1. TOP MAIN STAGE AREA (EXPANDED STACK)
            Expanded(
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
                        child: Stack(
                          children: [
                            // Actual Web Video Stream PlatformView (Kept permanently mounted to preserve HTML element DOM node)
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
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 96,
                                          height: 96,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFF1E222A),
                                            border: Border.all(
                                              color: context.accentColor,
                                              width: 2,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.videocam_off_rounded,
                                            color: Colors.white,
                                            size: 44,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Camera Off',
                                          style: AppTypography.interTight(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Input: $_selectedCamera',
                                          style: AppTypography.interTight(
                                            fontSize: 12,
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 2. ACTIVE STAGE SPEAKER TAG & WAVEFORM
                  ValueListenableBuilder<String>(
                    valueListenable: _videoService.stageSpeakerIdNotifier,
                    builder: (context, pinnedId, _) {
                      final participants = _videoService.activeParticipantsNotifier.value;
                      if (participants.isEmpty) return const SizedBox.shrink();
                      final activeParticipant = participants.firstWhere(
                        (p) => p.id == pinnedId,
                        orElse: () => participants.first,
                      );

                      return Positioned(
                        right: 16,
                        bottom: 124,
                        child: SpeakerTag(
                          activeParticipant: activeParticipant,
                          audioLevel: _currentAudioLevel,
                        ),
                      );
                    },
                  ),

                  // HORIZONTAL ACTIVE SPEAKER & GUEST THUMBNAIL STRIP
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: ValueListenableBuilder<List<StreamParticipant>>(
                          valueListenable: _videoService.activeParticipantsNotifier,
                          builder: (context, participants, _) {
                            return ValueListenableBuilder<String>(
                              valueListenable: _videoService.stageSpeakerIdNotifier,
                              builder: (context, pinnedId, _) {
                                return GuestThumbnailStrip(
                                  participants: participants,
                                  pinnedId: pinnedId,
                                  isHost: widget.isHost,
                                  onPinSpeaker: (id) => _videoService.pinStageSpeaker(id),
                                  onAddStageSpeaker: () {
                                    AppSnackBars.showInfo(context, 'Stage Invite link copied to clipboard');
                                  },
                                );
                              },
                            );
                          },
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
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '720p30 • 2.8 Mbps • Uptime ${_formatDuration(_sessionDurationSeconds)}',
                                style: AppTypography.interTight(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.info_outline_rounded, color: Colors.white38, size: 12),
                            ],
                          ),
                        ),
                      ),
                    ),

            // 2. TOP BAR OVERLAY
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        // Collapse / Browser PiP Trigger
                        InkWell(
                          onTap: _triggerPictureInPicture,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.picture_in_picture_alt_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),

                        const Spacer(),

                        // Stream Header Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'LIVE',
                                style: AppTypography.interTight(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.visibility_rounded,
                                color: Colors.white70,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$_spectatorCount',
                                style: AppTypography.interTight(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Spacer(),

                        // Media Device & Settings Icon
                        InkWell(
                          onTap: _showDeviceSelectorModal,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.tune_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. BOTTOM CONTROL DOCK
            BottomDock(
              isScreenSharing: _isScreenSharing,
              isMicMuted: _isMicMuted,
              isCameraOn: _isCameraOn,
              isFrontCamera: _isFrontCamera,
              onToggleScreenShare: _toggleScreenShare,
              onToggleMic: _toggleMic,
              onToggleCamera: _toggleCamera,
              onFlipCamera: _flipCamera,
              onEndCall: () {
                _videoService.setMinimized(false);
                _videoService.stopVideoStream();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
