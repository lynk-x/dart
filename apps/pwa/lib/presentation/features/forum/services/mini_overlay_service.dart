import 'package:flutter/foundation.dart';

enum MiniOverlayType {
  liveCall,
  liveStream,
}

/// Immutable state model holding all Mini Overlay configuration and runtime status.
class MiniOverlayState {
  final bool isLive;
  final bool isConnecting;
  final bool isMinimized;
  final MiniOverlayType streamType;
  final String hostName;
  final String forumName;

  const MiniOverlayState({
    this.isLive = false,
    this.isConnecting = false,
    this.isMinimized = false,
    this.streamType = MiniOverlayType.liveStream,
    this.hostName = '',
    this.forumName = '',
  });

  MiniOverlayState copyWith({
    bool? isLive,
    bool? isConnecting,
    bool? isMinimized,
    MiniOverlayType? streamType,
    String? hostName,
    String? forumName,
  }) {
    return MiniOverlayState(
      isLive: isLive ?? this.isLive,
      isConnecting: isConnecting ?? this.isConnecting,
      isMinimized: isMinimized ?? this.isMinimized,
      streamType: streamType ?? this.streamType,
      hostName: hostName ?? this.hostName,
      forumName: forumName ?? this.forumName,
    );
  }
}

/// Centralized service for managing floating In-App Mini Overlay state.
/// Independent of underlying WebRTC media implementations for video streams and audio calls.
class MiniOverlayService {
  static final MiniOverlayService _instance = MiniOverlayService._internal();
  factory MiniOverlayService() => _instance;
  MiniOverlayService._internal();

  /// Consolidated single ValueNotifier holding full state snapshot.
  final ValueNotifier<MiniOverlayState> stateNotifier =
      ValueNotifier<MiniOverlayState>(const MiniOverlayState());

  MiniOverlayState get state => stateNotifier.value;

  // Backwards compatibility getters
  bool get isMinimized => state.isMinimized;
  bool get isLive => state.isLive;
  bool get isConnecting => state.isConnecting;
  MiniOverlayType get streamType => state.streamType;
  String get hostName => state.hostName;
  String get forumName => state.forumName;

  /// Activates Mini Overlay mode for a Live Call (Audio strip)
  void activateLiveCall({
    required String hostName,
    String forumName = '',
    bool isConnecting = false,
  }) {
    stateNotifier.value = state.copyWith(
      hostName: hostName,
      forumName: forumName,
      streamType: MiniOverlayType.liveCall,
      isLive: true,
      isMinimized: true,
      isConnecting: isConnecting,
    );
  }

  /// Activates Mini Overlay mode for a Live Stream (Video canvas)
  void activateLiveStream({required String hostName, String forumName = ''}) {
    stateNotifier.value = state.copyWith(
      hostName: hostName,
      forumName: forumName,
      streamType: MiniOverlayType.liveStream,
      isLive: true,
      isMinimized: false,
      isConnecting: false,
    );
  }

  /// Updates or explicitly sets connecting state
  void setConnecting(bool connecting) {
    stateNotifier.value = state.copyWith(isConnecting: connecting);
  }

  /// Toggles or explicitly sets minimized state
  void setMinimized(bool minimized) {
    stateNotifier.value = state.copyWith(isMinimized: minimized);
  }

  /// Ends Mini Overlay session and hides overlay
  void endPipSession() {
    stateNotifier.value = state.copyWith(
      isLive: false,
      isConnecting: false,
      isMinimized: false,
    );
  }
}