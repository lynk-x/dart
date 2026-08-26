import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'pip_service.dart';
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

@JS('window.lynkVideoStreamHelper.publishCloudflareTracks')
external JSPromise<JSBoolean> _jsPublishCloudflareTracks(JSString appId, JSString sessionId);

@JS('window.lynkVideoStreamHelper.getTelemetryStats')
external JSPromise<JSString> _jsGetTelemetryStats();

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

  final ValueNotifier<bool> isMinimizedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLiveNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<StreamType> streamTypeNotifier =
      ValueNotifier<StreamType>(StreamType.liveStream);
  final ValueNotifier<bool> isLowBandwidthNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<TelemetryData> telemetryNotifier =
      ValueNotifier<TelemetryData>(const TelemetryData());
  final ValueNotifier<StageLayoutMode> stageLayoutNotifier =
      ValueNotifier<StageLayoutMode>(StageLayoutMode.focus);

  void toggleLowBandwidthMode([bool? enabled]) {
    isLowBandwidthNotifier.value = enabled ?? !isLowBandwidthNotifier.value;
  }

  final ValueNotifier<List<StreamParticipant>> activeParticipantsNotifier =
      ValueNotifier<List<StreamParticipant>>([]);

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

  String appId = '';
  String appSecret = '';
  String? cfSessionId;
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
    StreamPipService().setMinimized(minimized);
  }

  void setLive(bool live) {
    isLiveNotifier.value = live;
    if (!live) {
      isMinimizedNotifier.value = false;
      StreamPipService().endPipSession();
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

  /// Creates a new Cloudflare Calls WebRTC Session via REST API
  Future<String?> createCloudflareSession() async {
    if (appId.isEmpty || appSecret.isEmpty) {
      cfSessionId = 'mock_cf_session_${DateTime.now().millisecondsSinceEpoch}';
      return cfSessionId;
    }

    try {
      final response = await http.post(
        Uri.parse('https://rtc.live.cloudflare.com/v1/apps/$appId/sessions/new'),
        headers: {
          'Authorization': 'Bearer $appSecret',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        cfSessionId = data['sessionId'] as String?;
        return cfSessionId;
      }
    } catch (e) {
      debugPrint('[VideoStreamService] createCloudflareSession error: $e');
    }
    cfSessionId = 'mock_cf_session_${DateTime.now().millisecondsSinceEpoch}';
    return cfSessionId;
  }

  /// Publishes local video & audio WebRTC tracks to Cloudflare Calls SFU.
  /// No-op if tracks for the current [cfSessionId] are already published.
  Future<bool> publishCloudflareStream({String? customSessionId}) async {
    if (!kIsWeb) return true;
    final targetSessionId = customSessionId ?? cfSessionId ?? 'mock_cf_session';
    // Skip re-publishing if already live on the same session.
    if (_isPublished && customSessionId == null) return true;
    try {
      final res = await _jsPublishCloudflareTracks(appId.toJS, targetSessionId.toJS).toDart;
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
      final res = await _jsStartVideoStream(elementId.toJS, isFrontCamera.toJS).toDart;
      if (res.toDart) {
        publishCloudflareStream();
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
