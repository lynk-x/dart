import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:web/web.dart' as web;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import '../cubit/forum_chat_cubit.dart';
import '../cubit/forum_presence_cubit.dart';
import '../cubit/forum_updates_cubit.dart';
import '../models/forum_model.dart';
import '../services/stream_service.dart';
import 'message_input.dart';
import 'speaker_tag.dart';
import 'stage/stream_chat_overlay.dart';
import 'stage/stream_layout_overlays.dart';
import 'stage/stream_mode_selector.dart';
import 'stage/stream_telemetry_modal.dart';
import 'stage/stream_top_bar.dart';

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
  final bool _isMicMuted = false;
  final bool _isCameraOn = true;
  bool _isFrontCamera = true;
  bool _showTelemetryOverlay = false;
  final bool _showLiveChatOverlay = true;
  int _sessionDurationSeconds = 0;

  final List<Map<String, dynamic>> _unifiedStreamMessages = [
    {
      'id': 'm4',
      'type': 'chat',
      'sender': 'David_Dev',
      'role': 'Spectator',
      'text': 'Can we ask questions about offline sync capability?',
    },
    {
      'id': 'm3',
      'type': 'chat',
      'sender': 'Sarah_K',
      'role': 'Speaker',
      'text': 'Excited for the live feature announcement!',
    },
    {
      'id': 'm2',
      'type': 'announcement',
      'sender': 'Alex (Host)',
      'role': 'Organizer',
      'text': 'Welcome everyone! Taking Q&A right after the deck presentation.',
    },
    {
      'id': 'm1',
      'type': 'chat',
      'sender': 'Marcus',
      'role': 'VIP',
      'text': 'Great video clarity today! 🔥',
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
      ForumPresenceCubit? presenceCubit;
      try {
        presenceCubit = context.read<ForumPresenceCubit>();
      } catch (_) {}

      final online = presenceCubit?.state.onlineUsers ?? [];
      if (online.isEmpty) {
        setState(() {
          _videoService.spectatorCount += (1 - (DateTime.now().second % 3));
        });
      }
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
    StageTelemetryModal.show(
      context,
      videoService: _videoService,
      sessionDurationSeconds: _sessionDurationSeconds,
      formatDuration: _formatDuration,
    );
  }

  @override
  Widget build(BuildContext context) {
    ForumChatCubit? chatCubit;
    ForumUpdatesCubit? updatesCubit;
    ForumPresenceCubit? presenceCubit;
    try {
      chatCubit = context.watch<ForumChatCubit>();
    } catch (_) {}
    try {
      updatesCubit = context.watch<ForumUpdatesCubit>();
    } catch (_) {}
    try {
      presenceCubit = context.watch<ForumPresenceCubit>();
    } catch (_) {}

    final presenceUsers = presenceCubit?.state.onlineUsers ?? [];
    if (presenceUsers.isNotEmpty) {
      _videoService.spectatorCount = presenceUsers.length;
    }

    final chatMessages = chatCubit?.state.messages ?? [];
    final updateMessages = updatesCubit?.state.messages ?? [];

    List<Map<String, dynamic>> combinedStream = [];

    if (chatMessages.isNotEmpty || updateMessages.isNotEmpty) {
      for (final msg in chatMessages) {
        combinedStream.add({
          'id': msg.id,
          'type': msg.type == MessageType.announcement ? 'announcement' : 'chat',
          'sender': msg.sender,
          'role': msg.role == 'organizer' ? 'Organizer' : (msg.role ?? 'Spectator'),
          'text': msg.message,
          'createdAt': msg.createdAt,
        });
      }
      for (final msg in updateMessages) {
        combinedStream.add({
          'id': msg.id,
          'type': 'announcement',
          'sender': msg.sender,
          'role': 'Organizer',
          'text': msg.message,
          'createdAt': msg.createdAt,
        });
      }
      combinedStream.sort((a, b) => (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime));
      combinedStream = _processAndThrottleJoinMessages(combinedStream);
    } else {
      combinedStream = _unifiedStreamMessages;
    }

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
                child: Stack(
                  children: [
                    // Actual Web Video Stream PlatformView (Kept permanently mounted to preserve media streams across layout switches)
                    if (kIsWeb)
                      const Positioned.fill(
                        child: HtmlElementView(viewType: _viewType),
                      ),

                    // Stage Layout Mode Overlays
                    ValueListenableBuilder<StageLayoutMode>(
                      valueListenable: _videoService.stageLayoutNotifier,
                      builder: (context, layoutMode, _) {
                        if (layoutMode == StageLayoutMode.grid) {
                          return GridStageOverlay(
                            videoService: _videoService,
                            currentAudioLevel: _currentAudioLevel,
                          );
                        }
                        if (layoutMode == StageLayoutMode.presentation) {
                          return const PresentationStageOverlay();
                        }

                        // Focus / Deck mode Camera Off Overlay Placeholder
                        if (!_isCameraOn && !_isScreenSharing) {
                          return CameraOffOverlay(hostName: widget.hostName);
                        }

                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 16,
            right: 16,
            child: ValueListenableBuilder<StageLayoutMode>(
              valueListenable: _videoService.stageLayoutNotifier,
              builder: (context, layoutMode, _) {
                if (layoutMode == StageLayoutMode.grid) {
                  return const SizedBox.shrink();
                }
                return ValueListenableBuilder<List<StreamParticipant>>(
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
                );
              },
            ),
          ),

          // STAGE MODE SELECTOR OVERLAY (Bottom Left)
          Positioned(
            bottom: 16,
            left: 16,
            child: StageModeSelector(videoService: _videoService),
          ),

          // UNIFIED LIVE CHAT STREAM OVERLAY
          if (_showLiveChatOverlay)
            StageChatOverlay(combinedStream: combinedStream),

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
          StageTopBar(
            videoService: _videoService,
            sessionDurationSeconds: _sessionDurationSeconds,
            formatDuration: _formatDuration,
            showTelemetryOverlay: _showTelemetryOverlay,
            isHost: widget.isHost,
            isScreenSharing: _isScreenSharing,
            isFrontCamera: _isFrontCamera,
            onToggleTelemetry: () {
              setState(() {
                _showTelemetryOverlay = !_showTelemetryOverlay;
              });
            },
            onShowTelemetryModal: _showTelemetryDetailsModal,
            onMinimize: _triggerPictureInPicture,
            onToggleScreenShare: _toggleScreenShare,
            onFlipCamera: _flipCamera,
          ),
        ],
      ),
    );

    return Container(
      color: const Color(0xFF0F1115),
      child: Column(
        children: [
          mainStageArea,
          MessageInput(
            isOrganizer: widget.isHost,
            onSendMessage: (text, replyTo) {
              if (text.trim().isEmpty) return;

              if (widget.isHost) {
                // ORGANIZER MESSAGES -> EXCLUSIVELY POST TO UPDATES / ANNOUNCEMENTS
                ForumUpdatesCubit? updatesCubit;
                try {
                  updatesCubit = context.read<ForumUpdatesCubit>();
                } catch (_) {}

                if (updatesCubit != null) {
                  updatesCubit.sendMessage(
                    text,
                    isOrganizer: true,
                    isPremium: true,
                  );
                } else {
                  setState(() {
                    _unifiedStreamMessages.insert(0, {
                      'id': DateTime.now().millisecondsSinceEpoch.toString(),
                      'type': 'announcement',
                      'sender': widget.hostName.isNotEmpty ? widget.hostName : 'Host',
                      'role': 'Organizer',
                      'text': text,
                      'createdAt': DateTime.now(),
                    });
                  });
                }
              } else {
                // REGULAR ATTENDEES -> EXCLUSIVELY POST TO LIVE CHAT
                ForumChatCubit? chatCubit;
                try {
                  chatCubit = context.read<ForumChatCubit>();
                } catch (_) {}

                if (chatCubit != null) {
                  chatCubit.sendMessage(
                    text,
                    isOrganizer: false,
                    isPremium: true,
                  );
                } else {
                  setState(() {
                    _unifiedStreamMessages.insert(0, {
                      'id': DateTime.now().millisecondsSinceEpoch.toString(),
                      'type': 'chat',
                      'sender': 'You',
                      'role': 'Spectator',
                      'text': text,
                      'createdAt': DateTime.now(),
                    });
                  });
                }
              }
            },
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _processAndThrottleJoinMessages(
      List<Map<String, dynamic>> rawList) {
    if (rawList.isEmpty) return rawList;

    final List<Map<String, dynamic>> result = [];
    List<Map<String, dynamic>> pendingJoinBatch = [];

    for (final msg in rawList) {
      final text = (msg['text'] as String? ?? '');
      final isJoinMessage = text.contains('joined the live stream') ||
          text.contains('joined the live call') ||
          text.contains('joined the quiz session');

      if (isJoinMessage) {
        pendingJoinBatch.add(msg);
      } else {
        if (pendingJoinBatch.isNotEmpty) {
          result.add(_collapseJoinBatch(pendingJoinBatch));
          pendingJoinBatch = [];
        }
        result.add(msg);
      }
    }

    if (pendingJoinBatch.isNotEmpty) {
      result.add(_collapseJoinBatch(pendingJoinBatch));
    }

    return result;
  }

  Map<String, dynamic> _collapseJoinBatch(List<Map<String, dynamic>> batch) {
    if (batch.isEmpty) return {};
    if (batch.length == 1) return batch.first;

    final first = batch.first;
    final firstSender = first['sender'] as String? ?? 'A member';
    final countOthers = batch.length - 1;
    final text = (first['text'] as String? ?? '');

    String actionText = 'joined the live stream';
    String emoji = '👋';
    if (text.contains('live call')) {
      actionText = 'joined the live call';
      emoji = '🎙️';
    } else if (text.contains('quiz')) {
      actionText = 'joined the quiz session';
      emoji = '🎯';
    }

    final collapsedText =
        '$emoji $firstSender + $countOthers other${countOthers > 1 ? 's' : ''} $actionText';

    return {
      'id': 'batch_${first['id']}',
      'type': 'presence_join',
      'sender': 'System',
      'role': 'Presence',
      'text': collapsedText,
      'createdAt': first['createdAt'],
    };
  }
}
