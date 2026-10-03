import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;
import '../models/call_participant.dart';
import 'mini_overlay_service.dart';
import 'media_device_manager.dart';
export 'media_device_manager.dart';

@JS('window.lynkVideoStreamHelper.startVideoStream')
external JSPromise<JSBoolean> _jsStartVideoStream(JSString elementId, JSBoolean isFrontCamera);

@JS('window.lynkVideoStreamHelper.toggleCameraEnabled')
external void _jsToggleCameraEnabled(JSBoolean enabled);

@JS('window.lynkVideoStreamHelper.toggleMicEnabled')
external void _jsToggleMicEnabled(JSBoolean enabled);

@JS('window.lynkVideoStreamHelper.requestPictureInPicture')
external JSPromise<JSBoolean> _jsRequestPictureInPicture(JSString elementId);

@JS('window.lynkVideoStreamHelper.startScreenShare')
external JSPromise<JSBoolean> _jsStartScreenShare(JSString elementId);

@JS('window.lynkVideoStreamHelper.stopVideoStream')
external void _jsStopVideoStream();

@JS('window.lynkAudioStreamHelper.getAudioLevel')
external JSNumber _jsGetAudioLevel();

@JS('window.lynkVideoStreamHelper.setCameraMirror')
external void _jsSetCameraMirror(JSBoolean isMirrored);

@JS('window.lynkAudioStreamHelper.requestWakeLock')
external JSPromise<JSAny?> _jsRequestWakeLock();

@JS('window.lynkAudioStreamHelper.releaseWakeLock')
external JSPromise<JSAny?> _jsReleaseWakeLock();

// A video call's co-host audio pull goes through lynkAudioStreamHelper
// directly (same bridging pattern as getAudioLevel/requestWakeLock above),
// not through a separate ForumAudioStreamService instance — audio
// playback for ANY call (audio-only or video) is that JS helper's
// responsibility; ForumVideoStreamService only owns video.
@JS('window.lynkAudioStreamHelper.addParticipantTrack')
external JSPromise<JSBoolean> _jsAddAudioParticipantTrack(
  JSString edgeFunctionUrl,
  JSString authToken,
  JSString forumId,
  JSString participantUserId,
  JSString remoteSessionId,
  JSString remoteTrackName,
);

@JS('window.lynkAudioStreamHelper.removeParticipantTrack')
external void _jsRemoveAudioParticipantTrack(JSString participantUserId);

// Establishes the audio listener connection for a video call — previously
// this never existed at all: lynkVideoStreamHelper's recvonly transceiver
// is video-only, and nothing ever called lynkAudioStreamHelper
// .joinAsListener from the video call path, so a video call's host audio
// track (published alongside video — see publishCloudflareTracks) was
// never actually pulled by anyone. addParticipantAudioTrack (co-host audio,
// above) requires this connection to already exist, the same way
// lynkAudioStreamHelper.addParticipantTrack requires its own joinAsListener
// to have run first for an audio-only call.
@JS('window.lynkAudioStreamHelper.joinAsListener')
external JSPromise<JSBoolean> _jsJoinAudioListenerForVideoCall(
  JSString edgeFunctionUrl,
  JSString authToken,
  JSString forumId,
  JSString remoteSessionId,
  JSString remoteTrackName,
);

@JS('window.lynkAudioStreamHelper.stopListening')
external void _jsStopListeningAudioForVideoCall();

@JS('window.lynkVideoStreamHelper.publishCloudflareTracks')
external JSPromise<JSBoolean> _jsPublishCloudflareTracks(
  JSString appId,
  JSString sessionId,
  JSString edgeFunctionUrl,
  JSString authToken,
  JSString forumId,
  JSBoolean forceReconnect,
  JSString trackBaseName,
);

@JS('window.lynkVideoStreamHelper.joinAsVideoListener')
external JSPromise<JSBoolean> _jsJoinAsVideoListener(
  JSString elementId,
  JSString edgeFunctionUrl,
  JSString authToken,
  JSString forumId,
  JSString remoteSessionId,
  JSString remoteTrackName,
);

@JS('window.lynkVideoStreamHelper.stopListeningVideo')
external void _jsStopListeningVideo();

@JS('window.lynkVideoStreamHelper.addParticipantVideoTrack')
external JSPromise<JSBoolean> _jsAddParticipantVideoTrack(
  JSString edgeFunctionUrl,
  JSString authToken,
  JSString forumId,
  JSString participantUserId,
  JSString slotElementId,
  JSString remoteSessionId,
  JSString remoteTrackName,
);

@JS('window.lynkVideoStreamHelper.removeParticipantVideoTrack')
external void _jsRemoveParticipantVideoTrack(JSString participantUserId);

@JS('window.lynkVideoStreamHelper.getTelemetryStats')
external JSPromise<JSString> _jsGetTelemetryStats();

@JS('window.lynkVideoStreamHelper.getListenerTelemetryStats')
external JSPromise<JSString> _jsGetListenerTelemetryStats();

@JS('window.lynkVideoStreamHelper.setStreamQuality')
external JSPromise<JSBoolean> _jsSetStreamQuality(JSString elementId, JSString quality);

class TelemetryData {
  final int width;
  final int height;
  final int fps;
  final int rttMs;
  final String bitrateMbps;
  final String packetLossPercent;
  final String codec;

  const TelemetryData({
    this.width = 1280,
    this.height = 720,
    this.fps = 30,
    this.rttMs = 28,
    this.bitrateMbps = '2.8',
    this.packetLossPercent = '0.0',
    this.codec = 'H.264 / Opus',
  });

  String get resolutionLabel => '${height}p$fps';
  String get summaryLabel => '$resolutionLabel • $bitrateMbps Mbps';

  /// Evaluates connection quality to trigger automated Low-Bandwidth fallback mode
  bool get isPoorConnection {
    final loss = double.tryParse(packetLossPercent) ?? 0.0;
    return loss >= 5.0 || rttMs >= 250;
  }
}

class StreamParticipant {
  final String id;
  final String name;
  final String role;
  final String avatarUrl;
  final bool isHost;
  final bool isCameraOn;
  final bool isMicMuted;
  final bool isSpeaking;
  final bool isOnStage;

  const StreamParticipant({
    required this.id,
    required this.name,
    required this.role,
    this.avatarUrl = '',
    this.isHost = false,
    this.isCameraOn = true,
    this.isMicMuted = false,
    this.isSpeaking = false,
    this.isOnStage = true,
  });

  StreamParticipant copyWith({
    String? id,
    String? name,
    String? role,
    String? avatarUrl,
    bool? isHost,
    bool? isCameraOn,
    bool? isMicMuted,
    bool? isSpeaking,
    bool? isOnStage,
  }) {
    return StreamParticipant(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isHost: isHost ?? this.isHost,
      isCameraOn: isCameraOn ?? this.isCameraOn,
      isMicMuted: isMicMuted ?? this.isMicMuted,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isOnStage: isOnStage ?? this.isOnStage,
    );
  }
}

enum StageLayoutMode {
  focus,
  grid,
  presentation,
}

enum StreamType {
  liveCall,
  liveStream,
}

class ForumVideoStreamService {
  static final ForumVideoStreamService _instance = ForumVideoStreamService._internal();
  factory ForumVideoStreamService() => _instance;
  ForumVideoStreamService._internal();

  JSFunction? _listenerLostListener;
  JSFunction? _publishNeedsReconnectListener;
  JSFunction? _publishLostListener;

  /// Registers [onLost] to fire when the JS layer's listener-side retry
  /// (see audio_stream_helper.js's _scheduleListenerReconnect, video block)
  /// exhausts its 3 attempts and gives up reconnecting a dropped remote
  /// video track. Call [removeListenerLostCallback] when done (e.g. the
  /// stage widget's dispose()) to avoid leaking the JS-side event listener.
  void onRemoteVideoListenerLost(void Function() onLost) {
    if (!kIsWeb) return;
    removeListenerLostCallback();
    _listenerLostListener = ((web.Event event) => onLost()).toJS;
    web.window.addEventListener('lynkVideoListenerLost', _listenerLostListener);
  }

  void removeListenerLostCallback() {
    if (!kIsWeb || _listenerLostListener == null) return;
    web.window.removeEventListener('lynkVideoListenerLost', _listenerLostListener);
    _listenerLostListener = null;
  }

  /// Registers [onNeedsReconnect] to fire each time the JS layer's publish
  /// side detects its Cloudflare connection has failed/disconnected — see
  /// ForumAudioStreamService.onPublishNeedsReconnect for the full
  /// rationale (same mechanism, video's publish connection).
  void onPublishNeedsReconnect(void Function() onNeedsReconnect) {
    if (!kIsWeb) return;
    removePublishReconnectCallbacks();
    _publishNeedsReconnectListener = ((web.Event event) => onNeedsReconnect()).toJS;
    web.window.addEventListener('lynkVideoPublishNeedsReconnect', _publishNeedsReconnectListener);
  }

  /// Registers [onLost] to fire once the JS layer's publish-reconnect
  /// attempts are exhausted (3 attempts).
  void onPublishLost(void Function() onLost) {
    if (!kIsWeb) return;
    _publishLostListener = ((web.Event event) => onLost()).toJS;
    web.window.addEventListener('lynkVideoPublishLost', _publishLostListener);
  }

  void removePublishReconnectCallbacks() {
    if (!kIsWeb) return;
    if (_publishNeedsReconnectListener != null) {
      web.window.removeEventListener('lynkVideoPublishNeedsReconnect', _publishNeedsReconnectListener);
      _publishNeedsReconnectListener = null;
    }
    if (_publishLostListener != null) {
      web.window.removeEventListener('lynkVideoPublishLost', _publishLostListener);
      _publishLostListener = null;
    }
  }

  RealtimeChannel? _videoChannel;

  /// Realtime broadcast channel for video stream lifecycle events —
  /// previously video had NO signaling channel at all (listeners only
  /// ever pulled streaming_config once, on screen open), which meant there
  /// was no way to tell an already-joined listener that the host's
  /// Cloudflare session changed (e.g. after a publish reconnect). Mirrors
  /// ForumAudioStreamService.subscribeToAudioBroadcast exactly, one
  /// separate channel so a busy audio call elsewhere in the same forum
  /// doesn't cross-fire video listeners or vice versa.
  RealtimeChannel subscribeToVideoBroadcast({
    required String forumId,
    required void Function(Map<String, dynamic> payload) onEvent,
  }) {
    _videoChannel?.unsubscribe();
    _videoChannel = Supabase.instance.client.channel('forum_video:$forumId');

    _videoChannel!.onBroadcast(
      event: 'video_stream_event',
      callback: (payload) {
        onEvent(payload);
      },
    ).subscribe();

    return _videoChannel!;
  }

  Future<void> broadcastVideoEvent({
    required String action,
    String? sessionId,
    String? hostId,
    Map<String, dynamic>? extraData,
  }) async {
    if (_videoChannel == null) return;
    await _videoChannel!.sendBroadcastMessage(
      event: 'video_stream_event',
      payload: {
        'action': action,
        if (sessionId != null) 'sessionId': sessionId,
        if (hostId != null) 'hostId': hostId,
        if (extraData != null) ...extraData,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<void> unsubscribeVideoBroadcast() async {
    await _videoChannel?.unsubscribe();
    _videoChannel = null;
  }

  final ValueNotifier<bool> isMinimizedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLiveNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<StreamType> streamTypeNotifier =
      ValueNotifier<StreamType>(StreamType.liveStream);
  final ValueNotifier<bool> isLowBandwidthNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<TelemetryData> telemetryNotifier =
      ValueNotifier<TelemetryData>(const TelemetryData());
  final ValueNotifier<TelemetryData> listenerTelemetryNotifier =
      ValueNotifier<TelemetryData>(const TelemetryData());
  final ValueNotifier<StageLayoutMode> stageLayoutNotifier =
      ValueNotifier<StageLayoutMode>(StageLayoutMode.focus);

  void toggleLowBandwidthMode([bool? enabled]) {
    isLowBandwidthNotifier.value = enabled ?? !isLowBandwidthNotifier.value;
  }

  final ValueNotifier<List<StreamParticipant>> activeParticipantsNotifier =
      ValueNotifier<List<StreamParticipant>>([]);

  /// Active call participants, keyed by userId — the source of truth for
  /// who is actually publishing a track right now. Unlike
  /// [activeParticipantsNotifier] (forum presence, i.e. who's online —
  /// see syncWithPresenceUsers), this is sourced from
  /// social.forum_call_participants and only ever contains real participants.
  /// No cubit owns video call state (see ForumVideoStage), so this lives
  /// here the same way the other call-state notifiers already do.
  final ValueNotifier<Map<String, CallParticipant>> participantsNotifier =
      ValueNotifier<Map<String, CallParticipant>>({});

  final ValueNotifier<String> stageSpeakerIdNotifier =
      ValueNotifier<String>('');

  final ValueNotifier<bool> isStageLockedNotifier =
      ValueNotifier<bool>(false);

  bool isMicMuted = false;
  bool isCameraOn = true;
  bool isFrontCamera = true;
  String forumName = '';
  String hostName = '';
  bool isHost = true;
  int spectatorCount = 0;

  /// Set by the caller before createCloudflareSession()/publishCloudflareStream()
  /// — required by the cloudflare-calls-session Edge Function's forum
  /// membership authorization check.
  String forumId = '';

  String? cfSessionId;
  String? _cfAppId;

  /// Id of the social.forum_call_summaries row for the call this service is
  /// currently hosting — set by the caller after startCallSummary(),
  /// cleared after endCallSummary() closes it. Same bookkeeping role as
  /// ForumAudioStreamCubit._callSummaryId, just held here since video has
  /// no cubit of its own.
  String? callSummaryId;
  bool _isPublished = false;

  void setStageLayout(StageLayoutMode mode) {
    stageLayoutNotifier.value = mode;
  }

  /// Syncs online presence users from [ForumPresenceCubit] into [activeParticipantsNotifier].
  /// Preserves existing AV state (mic, camera, stage status) for active participants.
  void syncWithPresenceUsers(List<Map<String, dynamic>> presenceUsers) {
    if (presenceUsers.isEmpty) return;

    final currentParticipants = List<StreamParticipant>.from(activeParticipantsNotifier.value);
    final Map<String, StreamParticipant> existingMap = {
      for (var p in currentParticipants) p.id: p
    };

    final List<StreamParticipant> updatedList = [];

    for (final u in presenceUsers) {
      final uid = u['user_id'] as String? ?? u['id'] as String? ?? '';
      if (uid.isEmpty) continue;

      final name = u['user_name'] as String? ?? u['full_name'] as String? ?? 'Member';
      final isOrg = (u['is_organizer'] as bool?) ?? false;

      if (existingMap.containsKey(uid)) {
        final existing = existingMap[uid]!;
        updatedList.add(existing.copyWith(
          name: name,
          role: isOrg ? 'Host' : existing.role,
        ));
      } else {
        updatedList.add(StreamParticipant(
          id: uid,
          name: name,
          role: isOrg ? 'Host' : 'Audience',
          isHost: isOrg,
          isCameraOn: false,
          isMicMuted: true,
          isSpeaking: false,
          isOnStage: false,
        ));
      }
    }

    if (updatedList.isNotEmpty) {
      if (!_areParticipantsEqual(currentParticipants, updatedList)) {
        activeParticipantsNotifier.value = updatedList;
      }
    }
  }

  bool _areParticipantsEqual(List<StreamParticipant> a, List<StreamParticipant> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].name != b[i].name ||
          a[i].role != b[i].role ||
          a[i].isMicMuted != b[i].isMicMuted ||
          a[i].isCameraOn != b[i].isCameraOn ||
          a[i].isSpeaking != b[i].isSpeaking ||
          a[i].isOnStage != b[i].isOnStage) {
        return false;
      }
    }
    return true;
  }

  void toggleStageLock() {
    isStageLockedNotifier.value = !isStageLockedNotifier.value;
  }

  void muteAllParticipants() {
    activeParticipantsNotifier.value = activeParticipantsNotifier.value.map((p) {
      if (!p.isHost) {
        return p.copyWith(isMicMuted: true);
      }
      return p;
    }).toList();
  }

  void toggleParticipantMic(String participantId, {String? currentUserId}) {
    final list = List<StreamParticipant>.from(activeParticipantsNotifier.value);
    final index = list.indexWhere(
      (p) => p.id == participantId || (participantId == 'host' && p.isHost),
    );
    if (index != -1) {
      final nextMicMuted = !list[index].isMicMuted;
      list[index] = list[index].copyWith(isMicMuted: nextMicMuted);

      final isSelf = (currentUserId != null && currentUserId.isNotEmpty)
          ? (participantId == currentUserId || (list[index].isHost && participantId == 'host'))
          : (participantId == 'host' || list[index].isHost);

      if (isSelf) {
        toggleMic(!nextMicMuted);
      }
    } else {
      list.add(StreamParticipant(
        id: participantId,
        name: participantId,
        role: 'Speaker',
        isMicMuted: false,
        isCameraOn: false,
      ));
      if (participantId == 'host' || (currentUserId != null && participantId == currentUserId)) {
        toggleMic(true);
      }
    }
    activeParticipantsNotifier.value = list;
  }

  void toggleParticipantCamera(String participantId, {String? currentUserId}) {
    final list = List<StreamParticipant>.from(activeParticipantsNotifier.value);
    final index = list.indexWhere(
      (p) => p.id == participantId || (participantId == 'host' && p.isHost),
    );
    if (index != -1) {
      final nextCamOn = !list[index].isCameraOn;
      list[index] = list[index].copyWith(isCameraOn: nextCamOn);

      final isSelf = (currentUserId != null && currentUserId.isNotEmpty)
          ? (participantId == currentUserId || (list[index].isHost && participantId == 'host'))
          : (participantId == 'host' || list[index].isHost);

      if (isSelf) {
        toggleCamera(nextCamOn);
      }
    } else {
      list.add(StreamParticipant(
        id: participantId,
        name: participantId,
        role: 'Speaker',
        isMicMuted: true,
        isCameraOn: true,
      ));
      if (participantId == 'host' || (currentUserId != null && participantId == currentUserId)) {
        toggleCamera(true);
      }
    }
    activeParticipantsNotifier.value = list;
  }

  void toggleParticipantStage(String participantId) {
    activeParticipantsNotifier.value = activeParticipantsNotifier.value.map((p) {
      if (p.id == participantId) {
        return p.copyWith(isOnStage: !p.isOnStage);
      }
      return p;
    }).toList();
  }

  void pinStageSpeaker(String participantId) {
    stageSpeakerIdNotifier.value = participantId;
  }

  void updateHostSpeakerName(String name, {String? role, bool? isHostUser}) {
    if (name.isEmpty) return;
    hostName = name;
    final current = List<StreamParticipant>.from(activeParticipantsNotifier.value);
    final index = current.indexWhere((p) => p.id == 'host' || p.isHost);
    if (index != -1) {
      final old = current[index];
      current[index] = StreamParticipant(
        id: old.id,
        name: name,
        role: role ?? old.role,
        avatarUrl: old.avatarUrl,
        isHost: isHostUser ?? old.isHost,
        isCameraOn: old.isCameraOn,
        isMicMuted: old.isMicMuted,
        isSpeaking: old.isSpeaking,
      );
      activeParticipantsNotifier.value = current;
    }
  }

  void updateParticipantMediaState(String participantId, {bool? isMicMuted, bool? isCameraOn}) {
    final current = List<StreamParticipant>.from(activeParticipantsNotifier.value);
    final index = current.indexWhere((p) => p.id == participantId);
    if (index != -1) {
      final old = current[index];
      current[index] = StreamParticipant(
        id: old.id,
        name: old.name,
        role: old.role,
        avatarUrl: old.avatarUrl,
        isHost: old.isHost,
        isCameraOn: isCameraOn ?? old.isCameraOn,
        isMicMuted: isMicMuted ?? old.isMicMuted,
        isSpeaking: old.isSpeaking,
      );
      activeParticipantsNotifier.value = current;
    }
  }

  void setMinimized(bool minimized) {
    isMinimizedNotifier.value = minimized;
    MiniOverlayService().setMinimized(minimized);
  }

  void setLive(bool live) {
    isLiveNotifier.value = live;
    if (!live) {
      isMinimizedNotifier.value = false;
      MiniOverlayService().endPipSession();
    }
  }

  void setCameraMirror(bool isMirrored) {
    if (!kIsWeb) return;
    try {
      _jsSetCameraMirror(isMirrored.toJS);
    } catch (_) {}
  }

  void requestWakeLock() {
    if (!kIsWeb) return;
    try {
      _jsRequestWakeLock();
    } catch (_) {}
  }

  void releaseWakeLock() {
    if (!kIsWeb) return;
    try {
      _jsReleaseWakeLock();
    } catch (_) {}
  }

  /// Fetches real WebRTC telemetry stats from JS MediaStream / RTCPeerConnection
  Future<TelemetryData> fetchTelemetryStats() async {
    if (!kIsWeb) return telemetryNotifier.value;
    try {
      final rawJson = await _jsGetTelemetryStats().toDart;
      final data = jsonDecode(rawJson.toDart) as Map<String, dynamic>;
      final telemetry = TelemetryData(
        width: (data['width'] as num?)?.toInt() ?? 1280,
        height: (data['height'] as num?)?.toInt() ?? 720,
        fps: (data['fps'] as num?)?.toInt() ?? 30,
        rttMs: (data['rttMs'] as num?)?.toInt() ?? 28,
        bitrateMbps: (data['bitrateMbps'] as String?) ?? '2.8',
        packetLossPercent: (data['packetLossPercent'] as String?) ?? '0.0',
        codec: (data['codec'] as String?) ?? 'H.264 / Opus',
      );
      telemetryNotifier.value = telemetry;
      if (telemetry.isPoorConnection) {
        if (!isLowBandwidthNotifier.value) {
          isLowBandwidthNotifier.value = true;
          setStreamQuality('stage_video_element', '360p');
        }
      } else if (isLowBandwidthNotifier.value) {
        isLowBandwidthNotifier.value = false;
        setStreamQuality('stage_video_element', '720p');
      }
      return telemetry;
    } catch (e) {
      debugPrint('[VideoStreamService] fetchTelemetryStats error: $e');
      return telemetryNotifier.value;
    }
  }

  /// Fetches receive-side WebRTC telemetry for a LISTENER's own connection
  /// (see listenerTelemetryNotifier doc). Unlike fetchTelemetryStats, this
  /// doesn't call setStreamQuality — that only adjusts the HOST's own
  /// outgoing encode, which can't help a specific listener; Cloudflare's SFU
  /// is what picks which simulcast layer to forward per receiver; this
  /// method only reports the listener's own experienced quality so the UI
  /// can show it. (Explicit per-listener layer selection, if Cloudflare
  /// Calls exposes one, is unverified — see the simulcast publish comment
  /// in audio_stream_helper.js.)
  Future<TelemetryData> fetchListenerTelemetryStats() async {
    if (!kIsWeb) return listenerTelemetryNotifier.value;
    try {
      final rawJson = await _jsGetListenerTelemetryStats().toDart;
      final data = jsonDecode(rawJson.toDart) as Map<String, dynamic>;
      if (data['connected'] != true) return listenerTelemetryNotifier.value;

      final telemetry = TelemetryData(
        width: (data['width'] as num?)?.toInt() ?? 0,
        height: (data['height'] as num?)?.toInt() ?? 0,
        fps: (data['fps'] as num?)?.toInt() ?? 0,
        rttMs: (data['rttMs'] as num?)?.toInt() ?? 0,
        bitrateMbps: (data['bitrateMbps'] as String?) ?? '0.0',
        packetLossPercent: (data['packetLossPercent'] as String?) ?? '0.0',
        codec: 'H.264 / Opus',
      );
      listenerTelemetryNotifier.value = telemetry;
      return telemetry;
    } catch (e) {
      debugPrint('[VideoStreamService] fetchListenerTelemetryStats error: $e');
      return listenerTelemetryNotifier.value;
    }
  }

  final Map<String, Map<String, dynamic>> _localConfigCache = {};

  /// Fetches initial streaming_config for a forum on open — same
  /// forums.streaming_config JSONB column ForumAudioStreamService uses,
  /// distinguished by stream_type: 'video'. A forum can't run a live audio
  /// call and a live video stream at once today (both write the same
  /// column; the header already treats isAudioLive/isVideoStreamLive as
  /// mutually exclusive for display), so sharing the column matches the
  /// existing single-live-session-per-forum assumption rather than adding a
  /// new one. Reads through api.v1_forums (not the retired public.forums
  /// proxy).
  Future<Map<String, dynamic>?> fetchInitialStreamingConfig(String forumId) async {
    try {
      final data = await Supabase.instance.client
          .schema('api')
          .from('v1_forums')
          .select('streaming_config')
          .eq('id', forumId)
          .maybeSingle();

      if (data != null && data['streaming_config'] != null) {
        final config = Map<String, dynamic>.from(data['streaming_config']);
        if (config['stream_type'] == 'video') {
          _localConfigCache[forumId] = config;
          return config;
        }
        // A live audio call owns the column right now — nothing for video to join.
        return null;
      }
    } catch (e) {
      debugPrint('[VideoStreamService] fetchInitialStreamingConfig error: $e');
    }
    return _localConfigCache[forumId];
  }

  /// Updates streaming_config via the api.update_forum_streaming_config RPC
  /// (not a raw UPDATE against the retired public.forums proxy). Mirrors
  /// ForumAudioStreamService.updateForumStreamingConfig's shape/rollback
  /// behavior exactly, with stream_type: 'video'.
  /// [callSummaryId] (new): lets any client discover the active call's id
  /// to call joinAsCallParticipant/inviteCallParticipant/leaveCallParticipant — see the
  /// matching change on ForumAudioStreamService for the full rationale.
  /// allow_multi_speaker is now true for video too, now that the host
  /// claims their own slot through the same forum_call_participants
  /// registry a co-host would — this was previously hardcoded false from
  /// when video was single-publisher-only.
  Future<void> updateForumStreamingConfig({
    required String forumId,
    required bool isLive,
    String? sessionId,
    String? hostId,
    String? callSummaryId,
  }) async {
    final previousConfig = _localConfigCache[forumId];
    _localConfigCache[forumId] = {
      'is_live': isLive,
      'stream_type': 'video',
      'cf_session_id': sessionId,
      'active_host_id': hostId,
      'allow_multi_speaker': true,
      'call_summary_id': callSummaryId,
    };
    try {
      await Supabase.instance.client.schema('api').rpc('update_forum_streaming_config', params: {
        'p_forum_id': forumId,
        'p_is_live': isLive,
        'p_stream_type': 'video',
        'p_session_id': sessionId,
        'p_host_id': hostId,
        'p_call_summary_id': callSummaryId,
      });
    } catch (e) {
      debugPrint('[VideoStreamService] updateForumStreamingConfig error: $e');
      if (previousConfig != null) {
        _localConfigCache[forumId] = previousConfig;
      } else {
        _localConfigCache.remove(forumId);
      }
      rethrow;
    }
  }

  /// Opens a new social.forum_call_summaries row via the
  /// api.start_forum_call_summary RPC when a host starts a live stream —
  /// aggregate-only call history, mirrors ForumAudioStreamService
  /// .startCallSummary exactly with stream_type: 'video'. [hostId] is
  /// accepted for API symmetry but the RPC derives the real host from
  /// auth.uid(), not this param. Returns the new row's id so
  /// endCallSummary can close it; failures are swallowed (not critical-path).
  Future<String?> startCallSummary({
    required String forumId,
    required DateTime forumCreatedAt,
    required String hostId,
    String? sessionId,
  }) async {
    try {
      final response = await Supabase.instance.client.schema('api').rpc('start_forum_call_summary', params: {
        'p_forum_id': forumId,
        'p_forum_created_at': forumCreatedAt.toIso8601String(),
        'p_stream_type': 'video',
        'p_session_id': sessionId,
      });
      return response as String?;
    } catch (e) {
      debugPrint('[VideoStreamService] startCallSummary error: $e');
      return null;
    }
  }

  /// Sets ended_at on the call summary row created by [startCallSummary],
  /// via the api.end_forum_call_summary RPC.
  Future<void> endCallSummary(String? summaryId) async {
    if (summaryId == null) return;
    try {
      await Supabase.instance.client.schema('api').rpc('end_forum_call_summary', params: {
        'p_summary_id': summaryId,
      });
    } catch (e) {
      debugPrint('[VideoStreamService] endCallSummary error: $e');
    }
  }

  /// Claims a speaking slot in social.forum_call_participants for the
  /// calling user — the single source of truth for every active participant
  /// in a call, including the ORIGINAL HOST, who calls this the same way a
  /// self-joining co-host does. Returns the new participant row's id, or
  /// null on failure (cap reached, call ended, not an organizer).
  Future<String?> joinAsCallParticipant({
    required String forumId,
    required String callSummaryId,
    required String cfSessionId,
    required String trackName,
  }) async {
    try {
      final response = await Supabase.instance.client.schema('api').rpc('join_as_call_participant', params: {
        'p_forum_id': forumId,
        'p_call_summary_id': callSummaryId,
        'p_cf_session_id': cfSessionId,
        'p_track_name': trackName,
      });
      return response as String?;
    } catch (e) {
      debugPrint('[VideoStreamService] joinAsCallParticipant error: $e');
      return null;
    }
  }

  /// Host/organizer-only — grants [targetUserId] a speaking slot without
  /// requiring them to hold the organizer role themselves.
  Future<String?> inviteCallParticipant({
    required String forumId,
    required String callSummaryId,
    required String targetUserId,
    required String cfSessionId,
    required String trackName,
  }) async {
    try {
      final response = await Supabase.instance.client.schema('api').rpc('invite_call_participant', params: {
        'p_forum_id': forumId,
        'p_call_summary_id': callSummaryId,
        'p_user_id': targetUserId,
        'p_cf_session_id': cfSessionId,
        'p_track_name': trackName,
      });
      return response as String?;
    } catch (e) {
      debugPrint('[VideoStreamService] inviteCallParticipant error: $e');
      return null;
    }
  }

  /// Self-serve — voluntarily leaves the calling user's own speaking slot.
  Future<void> leaveCallParticipant(String callSummaryId) async {
    try {
      await Supabase.instance.client.schema('api').rpc('leave_call_participant', params: {
        'p_call_summary_id': callSummaryId,
      });
    } catch (e) {
      debugPrint('[VideoStreamService] leaveCallParticipant error: $e');
    }
  }

  /// Host/organizer-only — forcibly ends another participant's speaking
  /// slot.
  Future<void> removeCallParticipant({
    required String forumId,
    required String callSummaryId,
    required String targetUserId,
  }) async {
    try {
      await Supabase.instance.client.schema('api').rpc('remove_call_participant', params: {
        'p_forum_id': forumId,
        'p_call_summary_id': callSummaryId,
        'p_user_id': targetUserId,
      });
    } catch (e) {
      debugPrint('[VideoStreamService] removeCallParticipant error: $e');
    }
  }

  /// Self-serve — updates the calling user's OWN active participant row
  /// with a new Cloudflare address, after their publish connection was
  /// replaced (see _reconnectVideoPublish in ForumVideoStage).
  Future<void> updateParticipantSession({
    required String callSummaryId,
    required String cfSessionId,
    required String trackName,
  }) async {
    try {
      await Supabase.instance.client.schema('api').rpc('update_participant_session', params: {
        'p_call_summary_id': callSummaryId,
        'p_cf_session_id': cfSessionId,
        'p_track_name': trackName,
      });
    } catch (e) {
      debugPrint('[VideoStreamService] updateParticipantSession error: $e');
    }
  }

  /// Fetches the current active-speaker roster via api.v1_forum_call_participants
  /// — the bootstrap a listener/newly-joining client reconciles against
  /// before applying incremental participant_joined/participant_left
  /// broadcast events.
  Future<Map<String, CallParticipant>> fetchCallParticipants(String callSummaryId) async {
    try {
      final rows = await Supabase.instance.client
          .schema('api')
          .from('v1_forum_call_participants')
          .select('user_id, user_name, full_name, cf_session_id, track_name')
          .eq('call_summary_id', callSummaryId);
      final participants = <String, CallParticipant>{};
      for (final row in rows) {
        final participant = CallParticipant.fromJson(row);
        if (participant.userId.isNotEmpty) participants[participant.userId] = participant;
      }
      return participants;
    } catch (e) {
      debugPrint('[VideoStreamService] fetchCallParticipants error: $e');
      return {};
    }
  }

  /// Creates a new Cloudflare Calls WebRTC session via the cloudflare-calls-session
  /// Edge Function. The Cloudflare app secret is held server-side only — this
  /// never talks to rtc.live.cloudflare.com directly for session creation.
  Future<String?> createCloudflareSession(String forumId) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'cloudflare-calls-session',
        body: {'action': 'create_session', 'forumId': forumId},
      );

      if (response.status == 200) {
        cfSessionId = response.data?['sessionId'] as String?;
        _cfAppId = response.data?['appId'] as String?;
        return cfSessionId;
      }
      debugPrint('[VideoStreamService] createCloudflareSession returned status ${response.status}');
    } catch (e) {
      debugPrint('[VideoStreamService] createCloudflareSession error: $e');
    }
    return null;
  }

  /// Joins an already-live host's video session as a listener in a single
  /// Edge Function round-trip (session creation + remote track pull
  /// combined server-side via join_as_listener), pulling the host's
  /// published 'video' track into a peer connection targeting [elementId]
  /// (a DISTINCT DOM element from the local camera preview — see
  /// initCloudflareVideoListenerConnection). Same scaling rationale and
  /// single-track assumption as the audio listener path. On a dropped
  /// connection, the JS layer retries automatically (bounded at 3 attempts)
  /// without this method being called again.
  Future<bool> subscribeToRemoteVideo({
    required String elementId,
    required String forumId,
    required String hostSessionId,
  }) async {
    if (!kIsWeb) return false;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
      final res = await _jsJoinAsVideoListener(
        elementId.toJS,
        '$supabaseUrl/functions/v1'.toJS,
        (session?.accessToken ?? '').toJS,
        forumId.toJS,
        hostSessionId.toJS,
        'video'.toJS,
      ).toDart;
      return res.toDart;
    } catch (e) {
      debugPrint('[VideoStreamService] subscribeToRemoteVideo error: $e');
      return false;
    }
  }

  /// Adds a co-host's VIDEO track to the EXISTING listener connection —
  /// must be called after subscribeToRemoteVideo has already established a
  /// connection (pulling the host's track). [slotElementId] is one of a
  /// small fixed pool of pre-registered platform-view DOM element ids —
  /// see lynkVideoStreamHelper's _participantIdToSlotElementId comment for
  /// why slots instead of per-userId dynamic registration.
  Future<bool> addParticipantVideoTrack({
    required String forumId,
    required String participantUserId,
    required String slotElementId,
    required String remoteSessionId,
    required String remoteTrackName,
  }) async {
    if (!kIsWeb) return false;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
      final res = await _jsAddParticipantVideoTrack(
        '$supabaseUrl/functions/v1'.toJS,
        (session?.accessToken ?? '').toJS,
        forumId.toJS,
        participantUserId.toJS,
        slotElementId.toJS,
        remoteSessionId.toJS,
        remoteTrackName.toJS,
      ).toDart;
      return res.toDart;
    } catch (e) {
      debugPrint('[VideoStreamService] addParticipantVideoTrack error: $e');
      return false;
    }
  }

  /// Stops rendering a specific co-host's video — frees their slot
  /// element. Safe to call even if that participant's track was never added.
  void removeParticipantVideoTrack(String participantUserId) {
    if (!kIsWeb) return;
    try {
      _jsRemoveParticipantVideoTrack(participantUserId.toJS);
    } catch (e) {
      debugPrint('[VideoStreamService] removeParticipantVideoTrack error: $e');
    }
  }

  /// Adds a co-host's AUDIO track (video calls publish video and audio as
  /// two separate Cloudflare tracks) — bridges directly to
  /// lynkAudioStreamHelper, same pattern as getAudioLevel/requestWakeLock
  /// above. Must be called after the listener connection already exists
  /// (subscribeToRemoteVideo's audio-call counterpart,
  /// ForumAudioStreamService.subscribeToRemoteAudio, isn't used by video
  /// calls — audio playback is still lynkAudioStreamHelper's job
  /// regardless of call type).
  Future<bool> addParticipantAudioTrack({
    required String forumId,
    required String participantUserId,
    required String remoteSessionId,
    required String remoteTrackName,
  }) async {
    if (!kIsWeb) return false;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
      final res = await _jsAddAudioParticipantTrack(
        '$supabaseUrl/functions/v1'.toJS,
        (session?.accessToken ?? '').toJS,
        forumId.toJS,
        participantUserId.toJS,
        remoteSessionId.toJS,
        remoteTrackName.toJS,
      ).toDart;
      return res.toDart;
    } catch (e) {
      debugPrint('[VideoStreamService] addParticipantAudioTrack error: $e');
      return false;
    }
  }

  void removeParticipantAudioTrack(String participantUserId) {
    if (!kIsWeb) return;
    try {
      _jsRemoveAudioParticipantTrack(participantUserId.toJS);
    } catch (e) {
      debugPrint('[VideoStreamService] removeParticipantAudioTrack error: $e');
    }
  }

  /// Establishes the audio listener connection for a video call, pulling
  /// the HOST's audio track — must be called once, before any
  /// addParticipantAudioTrack call for a co-host (which only adds to an
  /// already-existing connection). See
  /// _jsJoinAudioListenerForVideoCall's comment for why this didn't exist
  /// at all before this change (a pre-existing gap, not new behavior being
  /// changed).
  Future<bool> subscribeToHostAudioForVideoCall({
    required String forumId,
    required String hostSessionId,
    required String remoteTrackName,
  }) async {
    if (!kIsWeb) return false;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
      final res = await _jsJoinAudioListenerForVideoCall(
        '$supabaseUrl/functions/v1'.toJS,
        (session?.accessToken ?? '').toJS,
        forumId.toJS,
        hostSessionId.toJS,
        remoteTrackName.toJS,
      ).toDart;
      return res.toDart;
    } catch (e) {
      debugPrint('[VideoStreamService] subscribeToHostAudioForVideoCall error: $e');
      return false;
    }
  }

  /// Tears down the listener-side peer connection and stops playback of the
  /// remote host's video. Safe to call even if never subscribed. Also
  /// tears down the SEPARATE audio listener connection
  /// subscribeToHostAudioForVideoCall established, if any — a video call's
  /// video and audio pulls are two independent connections (different JS
  /// helpers), so one teardown call doesn't imply the other.
  void unsubscribeFromRemoteVideo() {
    if (!kIsWeb) return;
    try {
      _jsStopListeningVideo();
    } catch (e) {
      debugPrint('[VideoStreamService] unsubscribeFromRemoteVideo error: $e');
    }
    try {
      _jsStopListeningAudioForVideoCall();
    } catch (e) {
      debugPrint('[VideoStreamService] unsubscribeFromRemoteVideo (audio) error: $e');
    }
  }

  /// Publishes local video & audio WebRTC tracks to Cloudflare Calls SFU.
  /// No-op if tracks for the current [cfSessionId] are already published.
  /// [trackBaseName] defaults to '' (today's single-publisher behavior,
  /// producing the unchanged literal track names 'video'/'audio'). Multi-
  /// speaker calls pass the speaker's own user id instead — see
  /// social.forum_call_participants.track_name and the matching comment on
  /// lynkVideoStreamHelper.publishCloudflareTracks for why one session
  /// still needs its video/audio tracks suffixed apart.
  Future<bool> publishCloudflareStream({
    String? customSessionId,
    bool forceReconnect = false,
    String trackBaseName = '',
  }) async {
    if (!kIsWeb) return true;
    final targetSessionId = customSessionId ?? cfSessionId;
    if (targetSessionId == null) {
      debugPrint('[VideoStreamService] publishCloudflareStream: no Cloudflare session — call createCloudflareSession first');
      return false;
    }
    // Skip re-publishing if already live on the same session.
    if (_isPublished && customSessionId == null && !forceReconnect) return true;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
      final res = await _jsPublishCloudflareTracks(
        (_cfAppId ?? '').toJS,
        targetSessionId.toJS,
        '$supabaseUrl/functions/v1'.toJS,
        (session?.accessToken ?? '').toJS,
        forumId.toJS,
        forceReconnect.toJS,
        trackBaseName.toJS,
      ).toDart;
      _isPublished = res.toDart;
      return _isPublished;
    } catch (e) {
      debugPrint('[VideoStreamService] publishCloudflareStream error: $e');
      return false;
    }
  }

  Future<bool> startScreenShare(String elementId) async {
    if (!kIsWeb) return false;
    try {
      final res = await _jsStartScreenShare(elementId.toJS).toDart;
      if (res.toDart) {
        publishCloudflareStream();
      }
      return res.toDart;
    } catch (e) {
      debugPrint('[VideoStreamService] startScreenShare error: $e');
      return false;
    }
  }

  Future<bool> startVideoStream(String elementId, {bool isFrontCamera = true}) async {
    if (!kIsWeb) return true;
    try {
      // The JS side unconditionally tears down any existing publish
      // connection/senders before re-acquiring media (needed for camera
      // flips and re-entering after screen share) — but that teardown
      // happens inside JS's own stopVideoStream(), not through this Dart
      // wrapper, so _isPublished was going stale: still true from the
      // FIRST publish, which made publishCloudflareStream()'s "already
      // published" guard skip republishing entirely after every camera
      // flip, silently leaving the new tracks never sent to Cloudflare.
      _isPublished = false;
      final res = await _jsStartVideoStream(elementId.toJS, isFrontCamera.toJS).toDart;
      if (res.toDart) {
        // trackBaseName = the publisher's own user id, so this video call's
        // Cloudflare tracks are addressed per-speaker like every other
        // publish path (audio calls, co-hosts) — see
        // social.forum_call_participants.track_name.
        final selfId = Supabase.instance.client.auth.currentUser?.id ?? '';
        publishCloudflareStream(trackBaseName: selfId);
      }
      return res.toDart;
    } catch (e) {
      debugPrint('[VideoStreamService] startVideoStream error: $e');
      return false;
    }
  }

  void toggleCamera(bool enabled) {
    if (!kIsWeb) return;
    try {
      _jsToggleCameraEnabled(enabled.toJS);
    } catch (_) {}
  }

  void toggleMic(bool enabled) {
    if (!kIsWeb) return;
    try {
      _jsToggleMicEnabled(enabled.toJS);
    } catch (_) {}
  }

  Future<bool> triggerPictureInPicture(String elementId) async {
    if (!kIsWeb) return false;
    try {
      final res = await _jsRequestPictureInPicture(elementId.toJS).toDart;
      return res.toDart;
    } catch (e) {
      debugPrint('[VideoStreamService] requestPictureInPicture error: $e');
      return false;
    }
  }

  void stopVideoStream() {
    setLive(false);
    releaseWakeLock();
    cfSessionId = null;
    _isPublished = false;
    if (!kIsWeb) return;
    try {
      _jsStopVideoStream();
    } catch (_) {}
  }

  double getAudioLevel() {
    if (!kIsWeb) return 0.0;
    try {
      return _jsGetAudioLevel().toDartDouble;
    } catch (_) {
      return 0.0;
    }
  }

  Future<List<MediaDevice>> getAvailableDevices() async {
    return MediaDeviceManager().getAvailableDevices();
  }

  Future<bool> switchAudioDevice(String deviceId) async {
    return MediaDeviceManager().switchAudioDevice(deviceId);
  }

  Future<bool> switchCameraDevice(String elementId, String deviceId) async {
    return MediaDeviceManager().switchCameraDevice(elementId, deviceId);
  }

  Future<bool> switchAudioOutputDevice(String elementId, String deviceId) async {
    return MediaDeviceManager().switchAudioOutputDevice(elementId, deviceId);
  }

  Future<bool> setStreamQuality(String elementId, String quality) async {
    if (!kIsWeb) return false;
    try {
      final res = await _jsSetStreamQuality(elementId.toJS, quality.toJS).toDart;
      return res.toDart;
    } catch (e) {
      debugPrint('[VideoStreamService] setStreamQuality error: $e');
      return false;
    }
  }
}
