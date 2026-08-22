import 'dart:async';
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:web/web.dart' as web;

import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import '../services/forum_video_stream_service.dart';

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
  int _spectatorCount = 142;
  String _selectedCamera = 'Built-in Front Camera';
  String _selectedAudioInput = 'Default Microphone';

  Timer? _spectatorTimer;
  Timer? _audioLevelTimer;
  double _currentAudioLevel = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      if (!_viewRegistered) {
        _videoElement = web.HTMLVideoElement()
          ..id = _elementId
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover';
        _videoElement!.setAttribute('playsinline', 'true');
        _videoElement!.setAttribute('autoplay', 'true');
        _videoElement!.setAttribute('muted', 'true');

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
    final success = await _videoService.startVideoStream(_elementId, isFrontCamera: _isFrontCamera);
    if (mounted && !success) {
      AppSnackBars.showInfo(context, 'Camera permission requested or offline preview active');
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
    _spectatorTimer?.cancel();
    _audioLevelTimer?.cancel();
    _videoService.releaseWakeLock();
    _videoService.stopVideoStream();
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
    _videoService.toggleCamera(_isCameraOn);
  }

  Future<void> _flipCamera() async {
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
    await _videoService.startVideoStream(_elementId, isFrontCamera: _isFrontCamera);
  }

  Future<void> _triggerPictureInPicture() async {
    final success = await _videoService.triggerPictureInPicture(_elementId);
    if (!success && mounted) {
      AppSnackBars.showInfo(context, 'Minimizing live stream');
      Navigator.of(context).pop();
    }
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
                  const SizedBox(height: 20),
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
        child: Stack(
          children: [
            // 1. VIDEO CANVAS STAGE
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
                      // Actual Web Video Stream PlatformView
                      if (kIsWeb && _isCameraOn)
                        const HtmlElementView(viewType: _viewType)
                      else
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Livestream Icon: Solid Container with Boundary Ring
                              Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isCameraOn ? context.accentColor : const Color(0xFF1E222A),
                                  border: Border.all(
                                    color: context.accentColor,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  _isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                                  color: Colors.white,
                                  size: 44,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _isCameraOn ? 'Live Stream Feed' : 'Camera Off',
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
                    ],
                  ),
                ),
              ),
            ),

            // Speaker Tag & Audio Amplitude Indicator Overlay
            Positioned(
              left: 16,
              bottom: 96,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      color: _isMicMuted ? Colors.redAccent : context.accentColor,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.hostName} (Host)',
                      style: AppTypography.interTight(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (!_isMicMuted && _currentAudioLevel > 0.05) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 6 + (14 * _currentAudioLevel),
                        decoration: BoxDecoration(
                          color: context.accentColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ],
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

                  // Live Telemetry Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
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
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
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
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Settings / Device Selector Button
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

            // 3. BOTTOM FLOATING CONTROL DOCK (5-Icon Format: Share, Mic, End Call (Center), Cam, Flip)
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF161920).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Position 1: Share Screen
                    IconButton(
                      icon: Icon(
                        _isScreenSharing
                            ? Icons.stop_screen_share_rounded
                            : Icons.screen_share_rounded,
                        color: _isScreenSharing ? context.accentColor : Colors.white,
                      ),
                      onPressed: _toggleScreenShare,
                      tooltip: _isScreenSharing ? 'Stop Screen Share' : 'Share Screen',
                    ),

                    // Position 2: Mic Toggle
                    IconButton(
                      icon: Icon(
                        _isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        color: _isMicMuted ? Colors.redAccent : Colors.white,
                      ),
                      onPressed: _toggleMic,
                      tooltip: _isMicMuted ? 'Unmute Mic' : 'Mute Mic',
                    ),

                    // Position 3 (DEAD CENTER): Red End Call Button
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(28),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.call_end_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),

                    // Position 4: Camera Toggle
                    IconButton(
                      icon: Icon(
                        _isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                        color: _isCameraOn ? Colors.white : Colors.redAccent,
                      ),
                      onPressed: _toggleCamera,
                      tooltip: _isCameraOn ? 'Turn Camera Off' : 'Turn Camera On',
                    ),

                    // Position 5: Flip Camera
                    IconButton(
                      icon: Icon(
                        Icons.flip_camera_ios_rounded,
                        color: _isFrontCamera ? Colors.white : context.accentColor,
                      ),
                      onPressed: _flipCamera,
                      tooltip: 'Flip Camera',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
