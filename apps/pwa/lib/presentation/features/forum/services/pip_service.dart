import 'package:flutter/foundation.dart';

enum PipStreamType {
  liveCall,
  liveStream,
}

/// Centralized service for managing floating In-App Picture-in-Picture (PiP) state.
/// Independent of underlying WebRTC media implementations for video streams and audio calls.
class StreamPipService {
  static final StreamPipService _instance = StreamPipService._internal();
  factory StreamPipService() => _instance;
  StreamPipService._internal();

  final ValueNotifier<bool> isMinimizedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLiveNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<PipStreamType> streamTypeNotifier =
      ValueNotifier<PipStreamType>(PipStreamType.liveStream);

  String hostName = '';
  String forumName = '';

  /// Activates PiP mode for a Live Call (Audio strip)
  void activateLiveCall({required String hostName, String forumName = ''}) {
    this.hostName = hostName;
    this.forumName = forumName;
    streamTypeNotifier.value = PipStreamType.liveCall;
    isLiveNotifier.value = true;
    isMinimizedNotifier.value = true;
  }

  /// Activates PiP mode for a Live Stream (Video canvas)
  void activateLiveStream({required String hostName, String forumName = ''}) {
    this.hostName = hostName;
    this.forumName = forumName;
    streamTypeNotifier.value = PipStreamType.liveStream;
    isLiveNotifier.value = true;
    isMinimizedNotifier.value = false;
  }

  /// Toggles or explicitly sets minimized state
  void setMinimized(bool minimized) {
    isMinimizedNotifier.value = minimized;
  }

  /// Ends PiP session and hides overlay
  void endPipSession() {
    isLiveNotifier.value = false;
    isMinimizedNotifier.value = false;
  }
}
