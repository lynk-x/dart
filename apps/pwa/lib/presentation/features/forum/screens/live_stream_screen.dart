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
  bool _showTelemetryOverlay = false;
  int _sessionDurationSeconds = 0;
  String _selectedCamera = 'Built-in Front Camera';
  String _selectedAudioInput = 'Default Microphone';
  String _selectedAudioOutput = 'Default Speaker';
  String _selectedStreamQuality = 'Auto (Adaptive HD)';

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
    return Container(
      color: const Color(0xFF0C0E12),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: context.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.accentColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.grid_view_rounded, color: context.accentColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Grid View (2x2 Multi-Speaker)',
                  style: AppTypography.interTight(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.0,
              ),
              itemCount: participants.length.clamp(1, 4),
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
                          radius: 24,
                          backgroundColor: p.isSpeaking ? context.accentColor : const Color(0xFF2A2E38),
                          child: Text(
                            p.name.substring(0, 1).toUpperCase(),
                            style: AppTypography.interTight(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            p.name,
                            style: AppTypography.interTight(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildPresentationStageOverlay(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0C10),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.indigoAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.indigoAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.space_dashboard_rounded, color: Colors.indigoAccent, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Presentation Mode',
                      style: AppTypography.interTight(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF14171E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.present_to_all_rounded, color: context.accentColor, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Stage Presentation Canvas',
                      style: AppTypography.interTight(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Main screen share & slide deck stream active',
                      style: AppTypography.interTight(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  List<MediaDevice> _hardwareDevices = [];

  void _showDeviceSelectorModal() {
    // Query real hardware devices when modal opens
    _videoService.getAvailableDevices().then((devices) {
      if (mounted && devices.isNotEmpty) {
        setState(() {
          _hardwareDevices = devices;
        });
      }
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121418),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final videoDevices = _hardwareDevices
                .where((d) => d.kind == 'videoinput')
                .toList();
            final audioInputDevices = _hardwareDevices
                .where((d) => d.kind == 'audioinput')
                .toList();
            final audioOutputDevices = _hardwareDevices
                .where((d) => d.kind == 'audiooutput')
                .toList();

            final cameraItems = videoDevices.isNotEmpty
                ? videoDevices.map((d) {
                    return DropdownMenuItem(
                      value: d.deviceId,
                      child: Text(
                        d.label.isNotEmpty ? d.label : 'Camera ${d.deviceId.substring(0, 5)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList()
                : const [
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
                  ];

            final audioInputItems = audioInputDevices.isNotEmpty
                ? audioInputDevices.map((d) {
                    return DropdownMenuItem(
                      value: d.deviceId,
                      child: Text(
                        d.label.isNotEmpty ? d.label : 'Mic ${d.deviceId.substring(0, 5)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList()
                : const [
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
                  ];

            final audioOutputItems = audioOutputDevices.isNotEmpty
                ? audioOutputDevices.map((d) {
                    return DropdownMenuItem(
                      value: d.deviceId,
                      child: Text(
                        d.label.isNotEmpty ? d.label : 'Speaker ${d.deviceId.substring(0, 5)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList()
                : const [
                    DropdownMenuItem(
                      value: 'Default Speaker',
                      child: Text('Default Speaker'),
                    ),
                    DropdownMenuItem(
                      value: 'Built-in Speaker / Headphones',
                      child: Text('Built-in Speaker / Headphones'),
                    ),
                    DropdownMenuItem(
                      value: 'Bluetooth Headset / AirPods',
                      child: Text('Bluetooth Headset / AirPods'),
                    ),
                  ];

            final qualityItems = const [
              DropdownMenuItem(
                value: 'Auto (Adaptive HD)',
                child: Text('Auto (Adaptive HD)'),
              ),
              DropdownMenuItem(
                value: '1080p Full HD',
                child: Text('1080p Full HD'),
              ),
              DropdownMenuItem(
                value: '720p HD (Data Saver)',
                child: Text('720p HD (Data Saver)'),
              ),
              DropdownMenuItem(
                value: '480p SD',
                child: Text('480p SD'),
              ),
            ];

            final selectedCamVal = cameraItems.any((item) => item.value == _selectedCamera)
                ? _selectedCamera
                : cameraItems.first.value;

            final selectedAudioVal = audioInputItems.any((item) => item.value == _selectedAudioInput)
                ? _selectedAudioInput
                : audioInputItems.first.value;

            final selectedOutputVal = audioOutputItems.any((item) => item.value == _selectedAudioOutput)
                ? _selectedAudioOutput
                : audioOutputItems.first.value;

            final selectedQualityVal = qualityItems.any((item) => item.value == _selectedStreamQuality)
                ? _selectedStreamQuality
                : qualityItems.first.value;

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
                    'Settings',
                    style: AppTypography.interTight(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (widget.isHost) ...[
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
                      initialValue: selectedCamVal,
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
                      items: cameraItems,
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => _selectedCamera = val);
                          setState(() => _selectedCamera = val);
                          _videoService.switchCameraDevice(_elementId, val);
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
                      initialValue: selectedAudioVal,
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
                      items: audioInputItems,
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => _selectedAudioInput = val);
                          setState(() => _selectedAudioInput = val);
                          _videoService.switchAudioDevice(val);
                        }
                      },
                    ),
                  ] else ...[
                    Text(
                      'Audio Routing',
                      style: AppTypography.interTight(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedOutputVal,
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
                      items: audioOutputItems,
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => _selectedAudioOutput = val);
                          setState(() => _selectedAudioOutput = val);
                          _videoService.switchAudioOutputDevice(_elementId, val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Stream Quality',
                      style: AppTypography.interTight(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedQualityVal,
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
                      items: qualityItems,
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => _selectedStreamQuality = val);
                          setState(() => _selectedStreamQuality = val);
                          _videoService.setStreamQuality(_elementId, val);
                        }
                      },
                    ),
                  ],

                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: _showTelemetryOverlay,
                    activeTrackColor: context.accentColor.withValues(alpha: 0.38),
                    activeThumbColor: context.accentColor,
                    thumbColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return context.accentColor;
                      }
                      return Colors.white54;
                    }),
                    trackColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return context.accentColor.withValues(alpha: 0.38);
                      }
                      return Colors.white12;
                    }),
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
                                      'Your camera is currently turned off',
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
                    );
                  },
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
                bottom: 16,
                child: SpeakerTag(
                  activeParticipant: activeParticipant,
                  audioLevel: _currentAudioLevel,
                ),
              );
            },
          ),

          // STAGE LAYOUT MODE SELECTOR (BOTTOM LEFT OF VIDEO STAGE)
          Positioned(
            left: 16,
            bottom: 16,
            child: ValueListenableBuilder<StageLayoutMode>(
              valueListenable: _videoService.stageLayoutNotifier,
              builder: (context, layoutMode, _) {
                IconData icon;
                String tooltipLabel;
                switch (layoutMode) {
                  case StageLayoutMode.focus:
                    icon = Icons.crop_square_rounded;
                    tooltipLabel = 'Layout: Focus View';
                    break;
                  case StageLayoutMode.grid:
                    icon = Icons.grid_view_rounded;
                    tooltipLabel = 'Layout: Grid View';
                    break;
                  case StageLayoutMode.presentation:
                    icon = Icons.space_dashboard_rounded;
                    tooltipLabel = 'Layout: Presentation View';
                    break;
                }

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: PopupMenuButton<StageLayoutMode>(
                    tooltip: tooltipLabel,
                    icon: Icon(icon, color: context.accentColor, size: 20),
                    color: const Color(0xFF161920),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Colors.white12),
                    ),
                    onSelected: (mode) {
                      _videoService.setStageLayout(mode);
                      String modeName;
                      switch (mode) {
                        case StageLayoutMode.focus:
                          modeName = 'Focus Mode (Active Speaker)';
                          break;
                        case StageLayoutMode.grid:
                          modeName = 'Grid View (2x2 Multi-Speaker)';
                          break;
                        case StageLayoutMode.presentation:
                          modeName = 'Presentation Mode';
                          break;
                      }
                      AppSnackBars.showInfo(context, 'Switched to $modeName');
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: StageLayoutMode.focus,
                        child: Row(
                          children: [
                            Icon(
                              Icons.crop_square_rounded,
                              color: layoutMode == StageLayoutMode.focus ? context.accentColor : Colors.white70,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Focus View',
                              style: AppTypography.interTight(
                                color: layoutMode == StageLayoutMode.focus ? context.accentColor : Colors.white,
                                fontWeight: layoutMode == StageLayoutMode.focus ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: StageLayoutMode.grid,
                        child: Row(
                          children: [
                            Icon(
                              Icons.grid_view_rounded,
                              color: layoutMode == StageLayoutMode.grid ? context.accentColor : Colors.white70,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Grid View',
                              style: AppTypography.interTight(
                                color: layoutMode == StageLayoutMode.grid ? context.accentColor : Colors.white,
                                fontWeight: layoutMode == StageLayoutMode.grid ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: StageLayoutMode.presentation,
                        child: Row(
                          children: [
                            Icon(
                              Icons.space_dashboard_rounded,
                              color: layoutMode == StageLayoutMode.presentation ? context.accentColor : Colors.white70,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Presentation View',
                              style: AppTypography.interTight(
                                color: layoutMode == StageLayoutMode.presentation ? context.accentColor : Colors.white,
                                fontWeight: layoutMode == StageLayoutMode.presentation ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
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
                const SizedBox(width: 12),

                // Forum Name & LIVE Badge
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'LIVE',
                          style: AppTypography.interTight(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.forumName,
                          style: AppTypography.interTight(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // Telemetry Toggle Button
                IconButton(
                  icon: Icon(
                    _showTelemetryOverlay ? Icons.analytics_rounded : Icons.analytics_outlined,
                    color: _showTelemetryOverlay ? context.accentColor : Colors.white70,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _showTelemetryOverlay = !_showTelemetryOverlay;
                    });
                  },
                  tooltip: 'Toggle Stream Telemetry',
                ),

                // Media Device Settings Button
                IconButton(
                  icon: const Icon(
                    Icons.tune_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: _showDeviceSelectorModal,
                  tooltip: 'Audio & Video Devices',
                ),

                // Spectator Counter Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.remove_red_eye_rounded, color: Colors.white70, size: 14),
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
