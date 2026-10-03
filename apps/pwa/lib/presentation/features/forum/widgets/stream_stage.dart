import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import '../cubit/forum_chat_cubit.dart';
import '../cubit/forum_presence_cubit.dart';
import '../cubit/forum_updates_cubit.dart';
import '../models/forum_model.dart';
import '../models/call_participant.dart';
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
  final String? forumId;
  static const String elementId = 'lynk_live_video_stage';

  const ForumVideoStage({
    super.key,
    this.forumName = 'Community Live Stream',
    this.hostName = 'Alex',
    this.isHost = true,
    this.forumId,
  });

  @override
  State<ForumVideoStage> createState() => _ForumVideoStageState();
}

class _ForumVideoStageState extends State<ForumVideoStage> with WidgetsBindingObserver {
  final ForumVideoStreamService _videoService = ForumVideoStreamService();

  static const String _elementId = ForumVideoStage.elementId;
  static const String _viewType = 'lynk-video-stage-view';
  static bool _viewRegistered = false;
  static web.HTMLVideoElement? _sharedVideoElement;

  // Fixed pool of pre-registered platform-view slots for co-hosts' video
  // tiles — matches GridStageOverlay's own existing clamp(1, 4) (the
  // default infra.system_config 'community'.max_call_speakers). Flutter
  // web view factories are meant to be registered upfront, not
  // dynamically per-userId at runtime; userIds aren't known ahead of time
  // but the cap is, so a fixed slot pool is allocated/reused instead — see
  // lynkVideoStreamHelper's _participantIdToSlotElementId comment for the
  // JS side of this same reasoning.
  static const int _maxParticipantSlots = 4;
  static const List<String> _participantSlotViewTypes = [
    'lynk-video-participant-slot-0',
    'lynk-video-participant-slot-1',
    'lynk-video-participant-slot-2',
    'lynk-video-participant-slot-3',
  ];
  static bool _participantSlotsRegistered = false;
  static final List<web.HTMLVideoElement> _participantSlotElements = [];
  // userId -> slot index, allocated as participants join, freed as they leave.
  final Map<String, int> _participantSlotAssignment = {};

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

    // Host starting stream defaults to Mic ON (_isMicMuted = false) & Camera ON (_isCameraOn = true).
    // Attendee joining stream defaults to Mic Muted (_isMicMuted = true) & Camera OFF (_isCameraOn = false).
    _isMicMuted = !widget.isHost;
    _isCameraOn = widget.isHost;

    if (kIsWeb) {
      _onScreenShareEndedListener = (web.Event event) {
        if (mounted && _isScreenSharing) {
          setState(() => _isScreenSharing = false);
        }
      }.toJS;
      web.window.addEventListener('lynkScreenShareEnded', _onScreenShareEndedListener);

      if (!widget.isHost) {
        // Fires once the JS layer's bounded reconnect (3 attempts) for a
        // dropped remote video track gives up.
        _videoService.onRemoteVideoListenerLost(() {
          if (mounted) {
            AppSnackBars.showInfo(context, 'Lost connection to the live stream.');
          }
        });
      } else {
        // Host-side counterpart: JS detected the publish connection failed.
        // Unlike the listener side, JS can't recover this itself —
        // Cloudflare's own guidance is to replace the connection (a NEW
        // session), which needs a Supabase-authenticated session-create
        // call, so the reconnect sequence runs here.
        _videoService.onPublishNeedsReconnect(() {
          unawaited(_reconnectVideoPublish());
        });
        _videoService.onPublishLost(() {
          if (mounted) {
            AppSnackBars.showInfo(context, 'Lost connection to your live stream. Please end and restart it.');
          }
        });
      }

      final fId = widget.forumId;
      if (fId != null && fId.isNotEmpty) {
        // Previously video had no realtime signaling at all — listeners
        // only ever fetched streaming_config once, on screen open, so
        // there was no way to tell an already-joined listener the host's
        // Cloudflare session changed (e.g. after a publish reconnect).
        _videoService.subscribeToVideoBroadcast(
          forumId: fId,
          onEvent: _handleVideoBroadcastEvent,
        );
      }

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

      if (!_participantSlotsRegistered) {
        for (final viewType in _participantSlotViewTypes) {
          final el = web.HTMLVideoElement()
            ..id = viewType
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.objectFit = 'cover';
          el.setAttribute('playsinline', 'true');
          el.setAttribute('autoplay', 'true');
          el.muted = true; // video tiles are silent — audio comes from the separate per-participant <audio> element
          _participantSlotElements.add(el);
          ui_web.platformViewRegistry.registerViewFactory(
            viewType,
            (int viewId) => el,
          );
        }
        _participantSlotsRegistered = true;
      }
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
  /// Host: only fetches when the telemetry overlay is visible (on-demand
  /// detail view, avoids redundant work). Listener: polls continuously at a
  /// slower 5s cadence regardless of the overlay — a struggling listener
  /// needs to see "your connection is poor" proactively (_PoorConnectionBadge
  /// below), not only once they've already opened a stats panel to ask why
  /// the video looks bad.
  void _startTelemetryPolling() {
    _telemetryTimer?.cancel();
    if (widget.isHost) {
      _telemetryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_showTelemetryOverlay) return;
        _videoService.fetchTelemetryStats();
      });
    } else {
      _telemetryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        _videoService.fetchListenerTelemetryStats();
      });
    }
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
    // Sort ascending so oldest messages appear first and newest messages appear at the bottom.
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
    _videoService.isMicMuted = _isMicMuted;
    _videoService.isCameraOn = _isCameraOn;

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
      if (widget.isHost) {
        if (_isCameraOn) {
          final success = await _videoService.startVideoStream(_elementId, isFrontCamera: _isFrontCamera);
          if (mounted && !success) {
            AppSnackBars.showInfo(context, 'Camera permission requested or offline preview active');
          }
        } else {
          _videoService.toggleCamera(false);
        }
      } else {
        // Listener: no local camera to start — pull the host's published
        // track into the same shared _elementId instead (there's no local
        // preview competing for it, unlike the audio listener path which
        // needs a distinct element from the host's own camera preview).
        await _subscribeToHostStream();
      }
    } else {
      _videoService.setMinimized(false);
    }
  }

  /// Fetches the persisted streaming_config for this forum and, if a live
  /// video session exists with a different host, pulls its track down and
  /// bootstraps the speaker registry (any co-hosts already in the call).
  /// Mirrors ForumAudioStreamCubit's initial-sync pattern — the Join Card
  /// that led here has no sessionId of its own to pass in.
  Future<void> _subscribeToHostStream() async {
    final forumId = widget.forumId;
    if (forumId == null || forumId.isEmpty) return;

    try {
      final config = await _videoService.fetchInitialStreamingConfig(forumId);
      if (!mounted || config == null || config['is_live'] != true) return;

      final sessionId = config['cf_session_id'] as String?;
      final callSummaryId = config['call_summary_id'] as String?;
      if (sessionId == null) return;

      final callParticipants = callSummaryId != null
          ? await _videoService.fetchCallParticipants(callSummaryId)
          : <String, CallParticipant>{};
      _videoService.participantsNotifier.value = callParticipants;
      if (!mounted) return;

      final success = await _videoService.subscribeToRemoteVideo(
        elementId: _elementId,
        forumId: forumId,
        hostSessionId: sessionId,
      );
      if (mounted && !success) {
        AppSnackBars.showInfo(context, 'Could not connect to the live stream — check your connection.');
      }
      if (!mounted || !success) return;

      // Establishes the SEPARATE audio listener connection (video calls
      // publish video and audio as two distinct Cloudflare tracks) — see
      // ForumVideoStreamService.subscribeToHostAudioForVideoCall's comment
      // for why this previously never happened at all for video calls.
      // The host's own registry entry (if the registry fetch above found
      // one — it may not have resolved yet right at call start) gives the
      // real trackName; falls back to the literal 'audio' default
      // publishCloudflareTracks uses when trackBaseName is empty.
      final hostParticipant = callParticipants.values.cast<CallParticipant?>().firstWhere(
            (s) => s?.cfSessionId == sessionId,
            orElse: () => null,
          );
      final hostAudioTrackName =
          hostParticipant != null ? '${hostParticipant.trackName}:audio' : 'audio';
      await _videoService.subscribeToHostAudioForVideoCall(
        forumId: forumId,
        hostSessionId: sessionId,
        remoteTrackName: hostAudioTrackName,
      );
      if (!mounted) return;

      // Pull any co-hosts already in the call (opening the forum well
      // after it started, or joining mid-call) — mirrors
      // ForumAudioStreamCubit._pullAllParticipantTracks.
      for (final participant in callParticipants.values) {
        if (participant.cfSessionId == sessionId) continue; // the host's own track, just pulled above
        await _pullParticipantMedia(participant);
      }
    } catch (e) {
      debugPrint('[ForumVideoStage] _subscribeToHostStream error: $e');
    }
  }

  /// Pulls both the video AND audio tracks for one co-host — a video call
  /// publishes them as two separate Cloudflare tracks
  /// (trackName:video/trackName:audio, see publishCloudflareTracks), so a
  /// listener needs two separate add_remote_track pulls, routed to two
  /// different places: video into this participant's slot element, audio
  /// into their own <audio> element (both via ForumVideoStreamService,
  /// which bridges to lynkAudioStreamHelper directly for the audio half —
  /// see addParticipantAudioTrack's comment).
  Future<void> _pullParticipantMedia(CallParticipant participant) async {
    final forumId = widget.forumId;
    if (forumId == null || forumId.isEmpty) return;

    final slotElementId = _allocateParticipantSlot(participant.userId);
    if (slotElementId != null) {
      await _videoService.addParticipantVideoTrack(
        forumId: forumId,
        participantUserId: participant.userId,
        slotElementId: slotElementId,
        remoteSessionId: participant.cfSessionId,
        remoteTrackName: '${participant.trackName}:video',
      );
    }

    await _videoService.addParticipantAudioTrack(
      forumId: forumId,
      participantUserId: participant.userId,
      remoteSessionId: participant.cfSessionId,
      remoteTrackName: '${participant.trackName}:audio',
    );
  }

  /// Assigns the next free slot to [userId], or returns the slot it
  /// already holds. Null if every slot is taken (shouldn't happen in
  /// practice — the speaker cap matches _maxParticipantSlots — but a late/
  /// duplicate event is handled gracefully rather than crashing).
  String? _allocateParticipantSlot(String userId) {
    final existing = _participantSlotAssignment[userId];
    if (existing != null) return _participantSlotViewTypes[existing];

    final taken = _participantSlotAssignment.values.toSet();
    for (var i = 0; i < _maxParticipantSlots; i++) {
      if (!taken.contains(i)) {
        _participantSlotAssignment[userId] = i;
        return _participantSlotViewTypes[i];
      }
    }
    debugPrint('[ForumVideoStage] No free participant slot for $userId — at capacity ($_maxParticipantSlots)');
    return null;
  }

  void _freeParticipantSlot(String userId) {
    _participantSlotAssignment.remove(userId);
  }

  /// Handles a video_stream_event broadcast: 'session_changed' (host's own
  /// _reconnectVideoPublish after its Cloudflare connection was replaced
  /// following a network drop — listener-only, the host is already on the
  /// new session by the time this fires for anyone else) or
  /// 'participant_joined'/'participant_left' (registry changes — kept
  /// current for everyone, host included, since the grid UI reads
  /// participantsNotifier regardless of role; track pull/teardown is
  /// listener-only, same reasoning as ForumAudioStreamCubit's audio
  /// equivalent).
  void _handleVideoBroadcastEvent(Map<String, dynamic> payload) {
    final action = payload['action'] as String?;

    if (action == 'participant_joined') {
      final participant = CallParticipant.fromJson(payload);
      if (participant.userId.isEmpty || participant.userId == Supabase.instance.client.auth.currentUser?.id) return;
      final updated = Map<String, CallParticipant>.from(_videoService.participantsNotifier.value);
      updated[participant.userId] = participant;
      _videoService.participantsNotifier.value = updated;

      if (!widget.isHost) {
        unawaited(_pullParticipantMedia(participant));
      }
      return;
    }

    if (action == 'participant_left') {
      final leftUserId = payload['userId'] as String?;
      if (leftUserId == null) return;
      final updated = Map<String, CallParticipant>.from(_videoService.participantsNotifier.value)
        ..remove(leftUserId);
      _videoService.participantsNotifier.value = updated;

      _videoService.removeParticipantVideoTrack(leftUserId);
      _videoService.removeParticipantAudioTrack(leftUserId);
      _freeParticipantSlot(leftUserId);
      return;
    }

    if (widget.isHost || action != 'session_changed') return;

    final newSessionId = payload['sessionId'] as String?;
    final forumId = widget.forumId;
    if (newSessionId == null || forumId == null || forumId.isEmpty) return;

    unawaited(() async {
      final success = await _videoService.subscribeToRemoteVideo(
        elementId: _elementId,
        forumId: forumId,
        hostSessionId: newSessionId,
      );
      if (mounted && !success) {
        AppSnackBars.showInfo(context, 'Could not reconnect to the live stream — check your connection.');
      }
    }());
  }

  bool _isReconnectingVideoPublish = false;

  /// Recovers the host's publish connection after the JS layer detects ICE
  /// failure/disconnect. Per Cloudflare's own guidance there is no
  /// supported same-session recovery for a publisher, so this replaces the
  /// connection entirely: a NEW Cloudflare session, republished tracks,
  /// the new session id persisted to BOTH streaming_config and this host's
  /// own forum_call_participants row (now the source of truth every
  /// participant, including the host, actually lives in), and a
  /// 'session_changed' broadcast so already-joined listeners re-pull
  /// against the new session (see _handleVideoBroadcastEvent). Mirrors
  /// ForumAudioStreamCubit._reconnectPublish exactly — video just has no
  /// cubit of its own, so this lives on the stage widget's state instead.
  Future<void> _reconnectVideoPublish() async {
    if (_isReconnectingVideoPublish || !_videoService.isLiveNotifier.value) {
      return;
    }
    final forumId = widget.forumId;
    if (forumId == null || forumId.isEmpty) return;

    _isReconnectingVideoPublish = true;
    try {
      final newSessionId = await _videoService.createCloudflareSession(forumId);
      if (!mounted || newSessionId == null) return;

      final userId = Supabase.instance.client.auth.currentUser?.id;

      final published = await _videoService.publishCloudflareStream(
        customSessionId: newSessionId,
        forceReconnect: true,
        trackBaseName: userId ?? '',
      );
      if (!mounted || !published) return;

      final callSummaryId = _videoService.callSummaryId;
      await _videoService.updateForumStreamingConfig(
        forumId: forumId,
        isLive: true,
        sessionId: newSessionId,
        hostId: userId,
        callSummaryId: callSummaryId,
      );
      if (callSummaryId != null && userId != null) {
        await _videoService.updateParticipantSession(
          callSummaryId: callSummaryId,
          cfSessionId: newSessionId,
          trackName: userId,
        );
      }
      if (!mounted) return;

      if (userId != null) {
        final updated = Map<String, CallParticipant>.from(_videoService.participantsNotifier.value);
        updated[userId] = CallParticipant(
          userId: userId,
          userName: widget.hostName,
          cfSessionId: newSessionId,
          trackName: userId,
        );
        _videoService.participantsNotifier.value = updated;
      }

      await _videoService.broadcastVideoEvent(
        action: 'session_changed',
        sessionId: newSessionId,
        hostId: userId,
      );
    } catch (e) {
      debugPrint('[ForumVideoStage] _reconnectVideoPublish error: $e');
    } finally {
      _isReconnectingVideoPublish = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (kIsWeb && _onScreenShareEndedListener != null) {
      web.window.removeEventListener('lynkScreenShareEnded', _onScreenShareEndedListener);
    }
    if (!widget.isHost) {
      _videoService.removeListenerLostCallback();
    } else {
      _videoService.removePublishReconnectCallbacks();
    }
    _audioLevelTimer?.cancel();
    _durationTimer?.cancel();
    _telemetryTimer?.cancel();
    _audioLevelNotifier.dispose();
    _sessionDurationNotifier.dispose();
    if (!_videoService.isMinimizedNotifier.value) {
      _videoService.releaseWakeLock();
      if (widget.isHost) {
        _videoService.stopVideoStream();
      } else {
        _videoService.unsubscribeFromRemoteVideo();
        _videoService.setLive(false);
      }
      unawaited(_videoService.unsubscribeVideoBroadcast());
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
                                participantSlotViewType: (userId) {
                                  final slot = _participantSlotAssignment[userId];
                                  return slot != null ? _participantSlotViewTypes[slot] : null;
                                },
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
            child: StageModeSelector(
              videoService: _videoService,
              onToggleMic: _toggleMic,
              onToggleCamera: _toggleCamera,
            ),
          ),

          // WEAK CONNECTION BADGE (listener only — see PoorConnectionBadge)
          if (!widget.isHost)
            ValueListenableBuilder<TelemetryData>(
              valueListenable: _videoService.listenerTelemetryNotifier,
              builder: (context, telemetry, _) {
                if (!telemetry.isPoorConnection) return const SizedBox.shrink();
                return const PoorConnectionBadge();
              },
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
              // Append to end of list so new messages appear at the bottom.
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

