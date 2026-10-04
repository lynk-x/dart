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
import '../cubit/forum_cubit.dart';
import '../cubit/forum_presence_cubit.dart';
import '../cubit/forum_updates_cubit.dart';
import '../models/forum_model.dart';
import '../models/call_participant.dart';
import '../services/call_sound_service.dart';
import '../services/mini_overlay_service.dart';
import '../services/stream_service.dart';
import 'header.dart' show ForumHeaderRole;
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
  // tiles — matches GridStageOverlay's clamp(1, 4) (default
  // infra.system_config 'community'.max_call_speakers). Flutter web view
  // factories must be registered upfront, not dynamically per-userId, so
  // a fixed pool is allocated/reused instead.
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

  StageLayoutMode? _lastLayoutMode;

  /// Switching layout mode remounts HtmlElementView(s) with the same
  /// viewType into a new parent — the underlying <video> element gets
  /// reparented in the DOM, which commonly freezes a live MediaStream's
  /// rendered frame until playback is re-triggered (see
  /// ForumVideoStreamService.resumeVideoPlayback). Only fires on an actual
  /// transition, once the new HtmlElementView(s) have mounted.
  void _nudgePlaybackOnLayoutChange(StageLayoutMode mode) {
    if (_lastLayoutMode == mode) return;
    _lastLayoutMode = mode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !kIsWeb) return;
      _videoService.resumeVideoPlayback(_elementId);
      for (final slotId in _participantSlotViewTypes) {
        _videoService.resumeVideoPlayback(slotId);
      }
    });
  }

  // --- Role ---
  // Mirrors _videoService.roleNotifier (the real source of truth) into
  // local State so build() reacts via setState rather than wrapping the
  // whole widget in a ValueListenableBuilder. widget.isHost stays the
  // permanent-host identity; _role is the current publish role, which a
  // co-host join/leave flips independently. A genuine listener is
  // required because joinAsVideoCoHost()/leaveVideoCoHost() can run from
  // the presence drawer while this widget isn't mounted (stage minimized),
  // so it must pick up a role change on next build.
  late ForumHeaderRole _role;
  bool get _isPublishingRole => _role == ForumHeaderRole.host || _role == ForumHeaderRole.speaker;

  void _onServiceRoleChanged() {
    if (!mounted || _role == _videoService.role) return;
    setState(() => _role = _videoService.role);
    _startTelemetryPolling();
  }

  /// Registers both the listener-side and publish-side JS connection
  /// callbacks unconditionally — a co-host is simultaneously a listener
  /// and a publisher, so both need to be live at once (role is checked
  /// inside each handler body, not at registration time). Called once
  /// from initState.
  void _registerConnectionCallbacks() {
    if (!kIsWeb) return;
    // Fires once the JS layer's bounded reconnect (3 attempts) for a
    // dropped remote video track gives up.
    _videoService.onRemoteVideoListenerLost(() {
      if (mounted) {
        AppSnackBars.showInfo(context, 'Lost connection to the live stream.');
      }
    });
    // Publish-side: JS detected the connection failed but can't recover it
    // itself — Cloudflare requires a new session, so the reconnect runs
    // here. No-op if not currently publishing (_reconnectVideoPublish checks).
    _videoService.onPublishNeedsReconnect(() {
      unawaited(_reconnectVideoPublish());
    });
    _videoService.onPublishLost(() {
      if (mounted && _isPublishingRole) {
        AppSnackBars.showInfo(context, _role == ForumHeaderRole.host
            ? 'Lost connection to your live stream. Please end and restart it.'
            : 'Lost connection to your speaking slot. Please rejoin as a speaker.');
      }
    });
  }

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

    // Host defaults to mic/camera on; attendee defaults to muted/camera off.
    _isMicMuted = !widget.isHost;
    _isCameraOn = widget.isHost;
    // _videoService.role survives minimize/restore — only seed it from
    // widget.isHost on a genuinely fresh session (still at the default
    // listener role); never downgrade an already-elevated role just
    // because this widget is re-mounting.
    if (widget.isHost || _videoService.role == ForumHeaderRole.listener) {
      _videoService.role = widget.isHost ? ForumHeaderRole.host : ForumHeaderRole.listener;
    }
    _role = _videoService.role;
    _videoService.roleNotifier.addListener(_onServiceRoleChanged);

    if (kIsWeb) {
      _onScreenShareEndedListener = (web.Event event) {
        if (mounted && _isScreenSharing) {
          setState(() => _isScreenSharing = false);
        }
      }.toJS;
      web.window.addEventListener('lynkScreenShareEnded', _onScreenShareEndedListener);

      _registerConnectionCallbacks();

      final fId = widget.forumId;
      if (fId != null && fId.isNotEmpty) {
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

  /// Polls telemetry from the video service. Publisher: only while the
  /// telemetry overlay is visible. Pure listener: polls continuously at a
  /// slower 5s cadence so a poor-connection badge can show proactively,
  /// without the listener needing to open a stats panel first.
  void _startTelemetryPolling() {
    _telemetryTimer?.cancel();
    if (_isPublishingRole) {
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
        // track into the same shared _elementId instead.
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

      // Establishes the separate audio listener connection (video calls
      // publish video and audio as two distinct Cloudflare tracks). The
      // host's registry entry, if resolved, gives the real trackName;
      // falls back to the literal 'audio' default otherwise.
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

  /// Pulls both the video and audio tracks for one co-host — a video call
  /// publishes them as two separate Cloudflare tracks
  /// (trackName:video/trackName:audio), routed to two places: video into
  /// this participant's slot element, audio into their own element.
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
  /// reconnect after a network drop), 'participant_joined'/'participant_left'
  /// (registry changes, kept current for everyone since the grid UI reads
  /// participantsNotifier regardless of role).
  void _handleVideoBroadcastEvent(Map<String, dynamic> payload) {
    final action = payload['action'] as String?;

    // _role == host means this is the host's own end-broadcast echoing
    // back to its sender (forum_screen.dart already tore down host state
    // before broadcasting) — nothing further to do. Everyone else tears
    // down the connection the server already force-closed their row for.
    if (action == 'end_stream') {
      if (_role == ForumHeaderRole.host) return;
      if (_isPublishingRole) {
        _videoService.stopVideoStream();
      }
      _videoService.unsubscribeFromRemoteVideo();
      _videoService.setLive(false);
      _videoService.releaseWakeLock();
      _videoService.participantsNotifier.value = {};
      _videoService.hostSessionIdNotifier.value = null;
      if (mounted) {
        setState(() {
          _role = ForumHeaderRole.listener;
          _isMicMuted = true;
          _isCameraOn = false;
        });
      }
      _videoService.role = ForumHeaderRole.listener;
      MiniOverlayService().endPipSession();
      unawaited(CallSoundService.playEnd());
      return;
    }

    if (action == 'participant_joined') {
      final participant = CallParticipant.fromJson(payload);
      if (participant.userId.isEmpty || participant.userId == Supabase.instance.client.auth.currentUser?.id) return;
      final updated = Map<String, CallParticipant>.from(_videoService.participantsNotifier.value);
      updated[participant.userId] = participant;
      _videoService.participantsNotifier.value = updated;

      // A co-host pulls every other participant's track too (listener to
      // everyone but themselves); only the host, who never pulls anyone,
      // skips this.
      if (_role != ForumHeaderRole.host) {
        unawaited(_pullParticipantMedia(participant));
      }
      return;
    }

    // Targeted at one user (payload['targetUserId']); every other client
    // receives this too (forum-wide channel) but ignores it.
    if (action == 'participant_invite') {
      final targetUserId = payload['targetUserId'] as String?;
      if (targetUserId != Supabase.instance.client.auth.currentUser?.id) return;
      final fromHostName = payload['fromHostName'] as String?;
      _videoService.pendingVideoInviteFromHostName.value = fromHostName ?? 'The host';
      return;
    }

    // The invitee accepted and already published their own track —
    // host-only, see ForumVideoStreamService.registerAcceptedVideoInvite.
    if (action == 'participant_invite_accepted') {
      if (_role != ForumHeaderRole.host) return;
      unawaited(_videoService.registerAcceptedVideoInvite(payload));
      return;
    }

    // Someone's mic/camera state changed. Ignore our own echo (already
    // updated locally in _toggleMic/_toggleCamera).
    if (action == 'media_state_changed') {
      final userId = payload['userId'] as String?;
      if (userId == null || userId == Supabase.instance.client.auth.currentUser?.id) return;
      final isMicMuted = payload['isMicMuted'] as bool?;
      final isCameraOn = payload['isCameraOn'] as bool?;
      // See _ownParticipantId's own comment on the 'host' sentinel — the
      // sender tells us directly which id it is rather than us guessing.
      final isHostUser = payload['isHost'] as bool? ?? false;
      _videoService.updateParticipantMediaState(
        isHostUser ? 'host' : userId,
        isMicMuted: isMicMuted,
        isCameraOn: isCameraOn,
      );
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

    // Same reasoning as participant_joined above — a co-host still needs
    // to re-pull the HOST's track on the host's own reconnect; only the
    // host itself (who IS the session that changed) skips this.
    if (_role == ForumHeaderRole.host || action != 'session_changed') return;

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

  /// Self-serve: a co-host (not the original host, who uses the end-stream
  /// flow in forum_screen.dart) leaves their speaking slot. Thin wrapper
  /// around ForumVideoStreamService.leaveVideoCoHost().
  Future<void> leaveVideoCoHost() async {
    await _videoService.leaveVideoCoHost();
    if (!mounted) return;
    setState(() {
      _role = ForumHeaderRole.listener;
      _isMicMuted = true;
      _isCameraOn = false;
    });
    _startTelemetryPolling();
    // Resume pulling the host's track into _elementId now that this tab's
    // own camera preview (same element) is gone.
    await _subscribeToHostStream();
  }

  bool _isReconnectingVideoPublish = false;

  /// Recovers this user's publish connection after ICE failure/disconnect
  /// (host or co-host). Mirrors ForumAudioStreamCubit._reconnectPublish's
  /// reconnect/rebroadcast strategy exactly — video just has no cubit of
  /// its own, so this lives on the stage widget's state instead.
  Future<void> _reconnectVideoPublish() async {
    if (_isReconnectingVideoPublish || !_videoService.isLiveNotifier.value || !_isPublishingRole) {
      return;
    }
    final forumId = widget.forumId;
    if (forumId == null || forumId.isEmpty) return;
    final isHost = _role == ForumHeaderRole.host;

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
      if (isHost) {
        await _videoService.updateForumStreamingConfig(
          forumId: forumId,
          isLive: true,
          sessionId: newSessionId,
          hostId: userId,
          callSummaryId: callSummaryId,
        );
        // The HOST's reconnected session is the new host session for
        // everyone, including the host's own Join Card instance — see
        // hostSessionIdNotifier's own comment.
        _videoService.hostSessionIdNotifier.value = newSessionId;
      }
      if (callSummaryId != null && userId != null) {
        await _videoService.updateParticipantSession(
          callSummaryId: callSummaryId,
          cfSessionId: newSessionId,
          trackName: userId,
        );
      }
      if (!mounted) return;

      CallParticipant? selfParticipant;
      if (userId != null) {
        selfParticipant = CallParticipant(
          userId: userId,
          userName: isHost ? widget.hostName : (context.read<ForumCubit>().state.userName.isNotEmpty
              ? context.read<ForumCubit>().state.userName
              : 'Speaker'),
          cfSessionId: newSessionId,
          trackName: userId,
        );
        final updated = Map<String, CallParticipant>.from(_videoService.participantsNotifier.value);
        updated[userId] = selfParticipant;
        _videoService.participantsNotifier.value = updated;
      }

      if (isHost) {
        await _videoService.broadcastVideoEvent(
          action: 'session_changed',
          sessionId: newSessionId,
          hostId: userId,
        );
      } else if (selfParticipant != null) {
        await _videoService.broadcastVideoEvent(
          action: 'participant_joined',
          extraData: selfParticipant.toBroadcastPayload(),
        );
      }
    } catch (e) {
      debugPrint('[ForumVideoStage] _reconnectVideoPublish error: $e');
    } finally {
      _isReconnectingVideoPublish = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoService.roleNotifier.removeListener(_onServiceRoleChanged);
    if (kIsWeb && _onScreenShareEndedListener != null) {
      web.window.removeEventListener('lynkScreenShareEnded', _onScreenShareEndedListener);
    }
    // Both registered unconditionally in _registerConnectionCallbacks()
    // (a co-host needs both simultaneously) — clean up both the same way.
    _videoService.removeListenerLostCallback();
    _videoService.removePublishReconnectCallbacks();
    _audioLevelTimer?.cancel();
    _durationTimer?.cancel();
    _telemetryTimer?.cancel();
    _audioLevelNotifier.dispose();
    _sessionDurationNotifier.dispose();
    if (!_videoService.isMinimizedNotifier.value) {
      _videoService.releaseWakeLock();
      // A co-host is both a publisher and a listener — stop/unsubscribe
      // both unconditionally, each a safe no-op if this user never held
      // that side. Deliberately NOT stopVideoStream()/setLive(false) for
      // either role: navigating away is this one client's own exit, not
      // the call ending — flipping isLiveNotifier here would wrongly show
      // "Session finished" to this user next time, even with the host
      // still broadcasting. Ending the call for everyone is only the
      // host's explicit 'end_stream' broadcast.
      if (_isPublishingRole) {
        _videoService.stopOwnVideoPublish();
      }
      _videoService.unsubscribeFromRemoteVideo();
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

  /// activeParticipantsNotifier keys the original host's entry by the
  /// literal sentinel id 'host', not their real userId; a co-host is keyed
  /// by their actual userId. Resolves which id this viewer's own
  /// mic/camera toggle should target.
  String get _ownParticipantId {
    if (_role == ForumHeaderRole.host) return 'host';
    return Supabase.instance.client.auth.currentUser?.id ?? 'host';
  }

  void _toggleMic() {
    setState(() => _isMicMuted = !_isMicMuted);
    _videoService.isMicMuted = _isMicMuted;
    _videoService.toggleMic(!_isMicMuted);
    _videoService.updateParticipantMediaState(_ownParticipantId, isMicMuted: _isMicMuted);
    _broadcastOwnMediaState();
  }

  void _toggleCamera() {
    setState(() => _isCameraOn = !_isCameraOn);
    _videoService.isCameraOn = _isCameraOn;
    _videoService.toggleCamera(_isCameraOn);
    _videoService.updateParticipantMediaState(_ownParticipantId, isCameraOn: _isCameraOn);
    _broadcastOwnMediaState();
  }

  /// Broadcasts this viewer's own mic/camera state to everyone else on the
  /// call — updateParticipantMediaState alone only updates this tab's local
  /// activeParticipantsNotifier, not other viewers' roster tiles.
  Future<void> _broadcastOwnMediaState() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    await _videoService.broadcastVideoEvent(
      action: 'media_state_changed',
      extraData: {
        'userId': userId,
        'isMicMuted': _isMicMuted,
        'isCameraOn': _isCameraOn,
        // Computed by the sender rather than guessed on receipt — avoids
        // every receiver needing its own "is this userId the host" lookup.
        'isHost': _role == ForumHeaderRole.host,
      },
    );
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
                        _nudgePlaybackOnLayoutChange(layoutMode);

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
                        role: _role == ForumHeaderRole.host ? 'Host' : 'Speaker',
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

          // WEAK CONNECTION BADGE — anyone who RECEIVES the host's track
          // (a pure listener, or a co-host who still pulls the host and
          // others) can have poor receive quality; only the host itself,
          // who pulls nothing, never shows this (see PoorConnectionBadge).
          if (_role != ForumHeaderRole.host)
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
            isPublishingRole: _isPublishingRole,
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

