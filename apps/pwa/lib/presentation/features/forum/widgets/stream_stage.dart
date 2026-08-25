import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
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
  static web.HTMLVideoElement? _sharedVideoElement;

  web.HTMLVideoElement? _videoElement;

  // --- UI state fields ---
  bool _isMicMuted = false;
  bool _isCameraOn = true;
  bool _isFrontCamera = true;
  bool _isScreenSharing = false;
  bool _showTelemetryOverlay = false;

  // --- Notifiers: update without triggering full build() rebuild ---
  /// Updated by the 100ms audio timer; consumed by SpeakerTag and GridStageOverlay
  /// via ValueListenableBuilder — no setState() needed.
  final ValueNotifier<double> _audioLevelNotifier = ValueNotifier(0.0);
  /// Updated by the 1s duration timer; consumed by StageTopBar's internal
  /// ValueListenableBuilder — avoids a full stage rebuild every second.
  final ValueNotifier<int> _sessionDurationNotifier = ValueNotifier(0);

  // --- Timers ---
  Timer? _audioLevelTimer;
  Timer? _durationTimer;
  Timer? _telemetryTimer;

  // --- Local stream message fallback (when cubit is unavailable) ---
  final List<StageChatEntry> _unifiedStreamMessages = [];

  // --- Memoization fields for combinedStream (fix #1) ---
  List<String> _lastChatMsgIds = const [];
  List<String> _lastUpdateMsgIds = const [];
  List<StageChatEntry> _combinedStream = const [];

  JSFunction? _onScreenShareEndedListener;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (kIsWeb) {
      _onScreenShareEndedListener = (web.Event event) {
        if (mounted && _isScreenSharing) {
          setState(() => _isScreenSharing = false);
        }
      }.toJS;
      web.window.addEventListener('lynkScreenShareEnded', _onScreenShareEndedListener);

      if (!_viewRegistered) {
        _sharedVideoElement = web.HTMLVideoElement()
          ..id = _elementId
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover';
        _sharedVideoElement!.setAttribute('playsinline', 'true');
        _sharedVideoElement!.setAttribute('autoplay', 'true');
        _sharedVideoElement!.setAttribute('muted', 'true');
        _sharedVideoElement!.muted = true;

        ui_web.platformViewRegistry.registerViewFactory(
          _viewType,
          (int viewId) => _sharedVideoElement!,
        );
        _viewRegistered = true;
      }
      _videoElement = _sharedVideoElement;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCameraAndAudio();
    });

    _startAudioLevelPolling();
    _startDurationTimer();
    _startTelemetryPolling();
  }

  // ---------------------------------------------------------------------------
  // Timers
  // ---------------------------------------------------------------------------

  /// Polls audio level every 100ms and updates [_audioLevelNotifier].
  /// Uses ValueNotifier.value = instead of setState() to avoid full rebuild.
  void _startAudioLevelPolling() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      if (_isMicMuted) {
        if (_audioLevelNotifier.value != 0.0) _audioLevelNotifier.value = 0.0;
        return;
      }
      final level = _videoService.getAudioLevel();
      if ((level - _audioLevelNotifier.value).abs() > 0.05) {
        _audioLevelNotifier.value = level;
      }
    });
  }

  /// Increments session duration every second via [_sessionDurationNotifier].
  /// Avoids setState() so only StageTopBar's internal ValueListenableBuilder
  /// rebuilds — not the entire stage widget tree.
  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _sessionDurationNotifier.value++;
    });
  }

  /// Polls telemetry stats from the video service every second.
  /// Only fetches when the telemetry overlay is visible to avoid redundant work.
  void _startTelemetryPolling() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_showTelemetryOverlay) return;
      _videoService.fetchTelemetryStats();
    });
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    final hours = totalSeconds ~/ 3600;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  // ---------------------------------------------------------------------------
  // Combined stream memoization 
  // ---------------------------------------------------------------------------

  /// Rebuilds [_combinedStream] only when the underlying cubit message IDs have
  /// changed. Skips the sort work on every build() call when nothing has changed
  /// — O(1) fast-reject on identical list lengths, O(N) ID comparison only when lengths match.
  void _maybeRebuildCombinedStream(
    List<ChatMessage> chatMsgs,
    List<ChatMessage> updateMsgs,
  ) {
    // Fast-reject: if list lengths differ, something definitely changed.
    // Only allocate ID lists when lengths match (the more expensive check).
    if (chatMsgs.length != _lastChatMsgIds.length ||
        updateMsgs.length != _lastUpdateMsgIds.length) {
      _lastChatMsgIds = chatMsgs.map((m) => m.id).toList();
      _lastUpdateMsgIds = updateMsgs.map((m) => m.id).toList();
    } else {
      final chatIds = chatMsgs.map((m) => m.id).toList();
      final updateIds = updateMsgs.map((m) => m.id).toList();
      if (listEquals(chatIds, _lastChatMsgIds) && listEquals(updateIds, _lastUpdateMsgIds)) {
        return; // Nothing changed — skip rebuild.
      }
      _lastChatMsgIds = chatIds;
      _lastUpdateMsgIds = updateIds;
    }

    final entries = <StageChatEntry>[
      for (final msg in chatMsgs)
        StageChatEntry(
          id: msg.id,
          type: msg.type == MessageType.announcement ? 'announcement' : 'chat',
          sender: msg.sender,
          role: msg.role == 'organizer' ? 'Organizer' : (msg.role ?? 'Spectator'),
          text: msg.message,
          createdAt: msg.createdAt,
        ),
      for (final msg in updateMsgs)
        StageChatEntry(
          id: msg.id,
          type: 'announcement',
          sender: msg.sender,
          role: 'Organizer',
          text: msg.message,
          createdAt: msg.createdAt,
        ),
    ];

    // Filter out join messages (no longer displayed in stage overlay).
    // Sort ascending so newest messages appear at the bottom.
    entries.removeWhere((e) =>
        e.text.contains('joined the live stream') ||
        e.text.contains('joined the live call') ||
        e.text.contains('joined the quiz session'));
    entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _combinedStream = entries;
  }

  // ---------------------------------------------------------------------------
  // App lifecycle
  // ---------------------------------------------------------------------------

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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (kIsWeb && _onScreenShareEndedListener != null) {
      web.window.removeEventListener('lynkScreenShareEnded', _onScreenShareEndedListener);
    }
    _audioLevelTimer?.cancel();
    _durationTimer?.cancel();
    _telemetryTimer?.cancel();
    _audioLevelNotifier.dispose();
    _sessionDurationNotifier.dispose();
    if (!_videoService.isMinimizedNotifier.value) {
      _videoService.releaseWakeLock();
      _videoService.stopVideoStream();
      if (kIsWeb && _videoElement != null) {
        _videoElement!.srcObject = null;
      }
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------------

  Future<void> _toggleScreenShare() async {
    if (_isScreenSharing) {
      await _videoService.startVideoStream(_elementId, isFrontCamera: _isFrontCamera);
      setState(() => _isScreenSharing = false);
    } else {
      final success = await _videoService.startScreenShare(_elementId);
      if (success) {
        setState(() => _isScreenSharing = true);
      } else if (mounted) {
        AppSnackBars.showInfo(context, 'Screen share cancelled or restricted on this mobile browser. Try Desktop or Chrome Android.');
      }
    }
  }

  void _toggleMic() {
    setState(() => _isMicMuted = !_isMicMuted);
    _videoService.isMicMuted = _isMicMuted;
    _videoService.toggleMic(!_isMicMuted);
    _videoService.updateParticipantMediaState('host', isMicMuted: _isMicMuted);
  }

  void _toggleCamera() {
    setState(() => _isCameraOn = !_isCameraOn);
    _videoService.isCameraOn = _isCameraOn;
    _videoService.toggleCamera(_isCameraOn);
    _videoService.updateParticipantMediaState('host', isCameraOn: _isCameraOn);
  }

  Future<void> _flipCamera() async {
    final nextFront = !_isFrontCamera;
    setState(() => _isFrontCamera = nextFront);
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
      sessionDurationSeconds: _sessionDurationNotifier.value,
      formatDuration: _formatDuration,
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ForumChatCubit? chatCubit;
    ForumUpdatesCubit? updatesCubit;
    ForumPresenceCubit? presenceCubit;
    try { chatCubit = context.watch<ForumChatCubit>(); } catch (_) {}
    try { updatesCubit = context.watch<ForumUpdatesCubit>(); } catch (_) {}
    try { presenceCubit = context.watch<ForumPresenceCubit>(); } catch (_) {}

    final presenceUsers = presenceCubit?.state.onlineUsers ?? [];
    if (presenceUsers.isNotEmpty) {
      _videoService.spectatorCount = presenceUsers.length;
    }

    // Rebuild combinedStream only when message IDs differ (memoized).
    final chatMessages = chatCubit?.state.messages ?? [];
    final updateMessages = updatesCubit?.state.messages ?? [];
    if (chatMessages.isNotEmpty || updateMessages.isNotEmpty) {
      _maybeRebuildCombinedStream(chatMessages, updateMessages);
    }
    final activeCombinedStream =
        (chatMessages.isNotEmpty || updateMessages.isNotEmpty) ? _combinedStream : _unifiedStreamMessages;

    // --- Main stage area ---
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
                child: ValueListenableBuilder<bool>(
                  valueListenable: _videoService.isLowBandwidthNotifier,
                  builder: (context, isLowBandwidth, _) {
                    return ValueListenableBuilder<StageLayoutMode>(
                      valueListenable: _videoService.stageLayoutNotifier,
                      builder: (context, layoutMode, _) {
                        final isGridMode = layoutMode == StageLayoutMode.grid;

                        return Stack(
                          children: [
                            // Actual Web Video Stream PlatformView for non-grid layout modes
                            if (kIsWeb && !isGridMode && !isLowBandwidth)
                              const Positioned.fill(
                                child: HtmlElementView(viewType: _viewType),
                              ),

                            if (isGridMode)
                              // _audioLevelNotifier is passed directly; GridStageOverlay
                              // reads .value for speaking detection and forwards the notifier
                              // to each SoundwaveWidget via listener — no extra VLB wrapper needed.
                              GridStageOverlay(
                                videoService: _videoService,
                                audioLevelNotifier: _audioLevelNotifier,
                                isCameraOn: _isCameraOn,
                                isMicMuted: _isMicMuted,
                                viewType: _viewType,
                              ),

                            if (layoutMode == StageLayoutMode.presentation)
                              const PresentationStageOverlay(),

                            // Focus / Deck mode Camera Off Overlay Placeholder
                            if (!isGridMode && !_isCameraOn && !_isScreenSharing && !isLowBandwidth)
                              CameraOffOverlay(hostName: widget.hostName),

                            // Low-Bandwidth Mode Overlay Placeholder
                            if (!isGridMode && isLowBandwidth)
                              LowBandwidthFallbackOverlay(hostName: widget.hostName),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),

          // SPEAKER TAG (Bottom Right) — scoped ValueListenableBuilder for audio level
          Positioned(
            bottom: 16,
            right: 16,
            child: ValueListenableBuilder<StageLayoutMode>(
              valueListenable: _videoService.stageLayoutNotifier,
              builder: (context, layoutMode, _) {
                if (layoutMode == StageLayoutMode.grid) return const SizedBox.shrink();
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
                    return ValueListenableBuilder<double>(
                      valueListenable: _audioLevelNotifier,
                      builder: (context, audioLevel, _) => SpeakerTag(
                        activeParticipant: activeParticipant,
                        audioLevel: audioLevel,
                      ),
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
          StageChatOverlay(combinedStream: activeCombinedStream),

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
                      return ValueListenableBuilder<int>(
                        valueListenable: _sessionDurationNotifier,
                        builder: (context, seconds, _) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.info_outline_rounded, color: Colors.white38, size: 12),
                              const SizedBox(width: 6),
                              Text(
                                '${telemetry.summaryLabel} • Uptime ${_formatDuration(seconds)}',
                                style: AppTypography.interTight(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),

          // TOP BAR OVERLAY
          StageTopBar(
            videoService: _videoService,
            sessionDurationNotifier: _sessionDurationNotifier,
            showTelemetryOverlay: _showTelemetryOverlay,
            isHost: widget.isHost,
            isScreenSharing: _isScreenSharing,
            isFrontCamera: _isFrontCamera,
            isMicMuted: _isMicMuted,
            isCameraOn: _isCameraOn,
            onToggleTelemetry: () {
              setState(() => _showTelemetryOverlay = !_showTelemetryOverlay);
            },
            onShowTelemetryModal: _showTelemetryDetailsModal,
            onMinimize: _triggerPictureInPicture,
            onToggleScreenShare: _toggleScreenShare,
            onFlipCamera: _flipCamera,
            onToggleMic: _toggleMic,
            onToggleCamera: _toggleCamera,
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
              // O(1) append — list is sorted ascending so new messages go at the end.
              _unifiedStreamMessages.add(StageChatEntry(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                type: widget.isHost ? 'announcement' : 'stream_chat',
                sender: widget.isHost
                    ? (widget.hostName.isNotEmpty ? widget.hostName : 'Host')
                    : 'You',
                role: widget.isHost ? 'Organizer' : 'Spectator',
                text: text,
                createdAt: DateTime.now(),
              ));
              // Only rebuild when using local fallback list (no cubit messages).
              if (chatCubit?.state.messages.isEmpty ?? true) {
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

}

