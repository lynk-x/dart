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

  /// Fetches available input/output hardware media devices (mics, cameras, speakers)
  Future<List<MediaDevice>> getAvailableDevices() async {
    if (!kIsWeb) return [];
    try {
      final rawJson = await _jsGetAvailableDevices().toDart;
      final List<dynamic> list = jsonDecode(rawJson.toDart);
      return list.map((item) {
        final map = item as Map<String, dynamic>;
        return MediaDevice(
          deviceId: map['deviceId'] as String? ?? '',
          kind: map['kind'] as String? ?? '',
          label: map['label'] as String? ?? 'Device',
        );
      }).toList();
    } catch (e) {
      debugPrint('[MediaDeviceManager] getAvailableDevices error: $e');
      return [];
    }
  }

  /// Switches active microphone input device
  Future<bool> switchAudioDevice(String deviceId) async {
    if (!kIsWeb) return false;
    try {
      final res = await _jsSwitchAudioDevice(deviceId.toJS).toDart;
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
      return res.toDart;
    } catch (e) {
      debugPrint('[MediaDeviceManager] switchAudioOutputDevice error: $e');
      return false;
    }
  }
}
