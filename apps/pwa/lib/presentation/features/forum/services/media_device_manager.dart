import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';

@JS('window.lynkVideoStreamHelper.getAvailableDevices')
external JSPromise<JSString> _jsGetAvailableDevices();

@JS('window.lynkVideoStreamHelper.switchAudioDevice')
external JSPromise<JSBoolean> _jsSwitchAudioDevice(JSString deviceId);

@JS('window.lynkVideoStreamHelper.switchCameraDevice')
external JSPromise<JSBoolean> _jsSwitchCameraDevice(JSString elementId, JSString deviceId);

@JS('window.lynkVideoStreamHelper.switchAudioOutputDevice')
external JSPromise<JSBoolean> _jsSwitchAudioOutputDevice(JSString elementId, JSString deviceId);

class MediaDevice {
  final String deviceId;
  final String kind;
  final String label;

  const MediaDevice({
    required this.deviceId,
    required this.kind,
    required this.label,
  });
}

/// Centralized manager for hardware media device enumeration & selection.
  /// Shared by audio calls and video broadcasts.
  class MediaDeviceManager {
    static final MediaDeviceManager _instance = MediaDeviceManager._internal();
    factory MediaDeviceManager() => _instance;
    MediaDeviceManager._internal();

    /// Cached device list. Null until the first successful enumeration —
    /// callers that need a fresh list can pass [forceRefresh: true].
    List<MediaDevice>? _cachedDevices;

    /// Fetches available input/output hardware media devices (mics, cameras, speakers).
  Future<List<MediaDevice>> getAvailableDevices({bool forceRefresh = false}) async {
    if (!kIsWeb) return [];
    if (!forceRefresh && _cachedDevices != null) return _cachedDevices!;
    try {
      final rawJson = await _jsGetAvailableDevices().toDart;
      final List<dynamic> list = jsonDecode(rawJson.toDart);
      _cachedDevices = list.map((item) {
        final map = item as Map<String, dynamic>;
        return MediaDevice(
          deviceId: map['deviceId'] as String? ?? '',
          kind: map['kind'] as String? ?? '',
          label: map['label'] as String? ?? 'Device',
        );
      }).toList();
      return _cachedDevices!;
    } catch (e) {
      debugPrint('[MediaDeviceManager] getAvailableDevices error: $e');
      return [];
    }
  }

  /// Invalidates the cached device list so the next [getAvailableDevices] call
  /// re-enumerates. Call after a device switch or if a device was unplugged.
  void invalidateCache() => _cachedDevices = null;

  /// Switches active microphone input device
  Future<bool> switchAudioDevice(String deviceId) async {
    if (!kIsWeb) return false;
    try {
      final res = await _jsSwitchAudioDevice(deviceId.toJS).toDart;
      if (res.toDart) invalidateCache();
      return res.toDart;
    } catch (e) {
      debugPrint('[MediaDeviceManager] switchAudioDevice error: $e');
      return false;
    }
  }

  /// Switches active camera video input device
  Future<bool> switchCameraDevice(String elementId, String deviceId) async {
    if (!kIsWeb) return false;
    try {
      final res = await _jsSwitchCameraDevice(elementId.toJS, deviceId.toJS).toDart;
      if (res.toDart) invalidateCache();
      return res.toDart;
    } catch (e) {
      debugPrint('[MediaDeviceManager] switchCameraDevice error: $e');
      return false;
    }
  }

  /// Switches active audio output device (speaker/headphones)
  Future<bool> switchAudioOutputDevice(String elementId, String deviceId) async {
    if (!kIsWeb) return false;
    try {
      final res = await _jsSwitchAudioOutputDevice(elementId.toJS, deviceId.toJS).toDart;
      if (res.toDart) invalidateCache();
      return res.toDart;
    } catch (e) {
      debugPrint('[MediaDeviceManager] switchAudioOutputDevice error: $e');
      return false;
    }
  }
}
