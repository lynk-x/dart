import 'package:flutter/foundation.dart';

enum MiniOverlayType {
  liveCall,
  liveStream,
}

/// Immutable state model holding all Mini Overlay configuration and runtime status.
class MiniOverlayState {
  final bool isLive;
  final bool isMinimized;
  final MiniOverlayType streamType;
  final String hostName;
  final String forumName;

  const MiniOverlayState({
    this.isLive = false,
    this.isMinimized = false,
    this.streamType = MiniOverlayType.liveStream,
    this.hostName = '',
    this.forumName = '',
  });

  MiniOverlayState copyWith({
    bool? isLive,
    bool? isMinimized,
    MiniOverlayType? streamType,
    String? hostName,
    String? forumName,
  }) {
    return MiniOverlayState(
      isLive: isLive ?? this.isLive,
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

  /// Consolidated single ValueNotifier holding full state snapshot
  final ValueNotifier<MiniOverlayState> stateNotifier =
      ValueNotifier<MiniOverlayState>(const MiniOverlayState());

  MiniOverlayState get state => stateNotifier.value;

  // Backwards compatibility getters
  bool get isMinimized => state.isMinimized;
  bool get isLive => state.isLive;
  MiniOverlayType get streamType => state.streamType;
  String get hostName => state.hostName;
  String get forumName => state.forumName;

  // Legacy individual ValueNotifier bridges for backwards compatibility with external listeners
  final ValueNotifier<bool> isMinimizedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLiveNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<MiniOverlayType> streamTypeNotifier =
      ValueNotifier<MiniOverlayType>(MiniOverlayType.liveStream);

  void _notifyLegacy() {
    isMinimizedNotifier.value = state.isMinimized;
    isLiveNotifier.value = state.isLive;
    streamTypeNotifier.value = state.streamType;
  }

  /// Activates Mini Overlay mode for a Live Call (Audio strip)
  void activateLiveCall({required String hostName, String forumName = ''}) {
    stateNotifier.value = state.copyWith(
      hostName: hostName,
      forumName: forumName,
      streamType: MiniOverlayType.liveCall,
      isLive: true,
      isMinimized: true,
    );
    _notifyLegacy();
  }

  /// Activates Mini Overlay mode for a Live Stream (Video canvas)
  void activateLiveStream({required String hostName, String forumName = ''}) {
    stateNotifier.value = state.copyWith(
      hostName: hostName,
      forumName: forumName,
      streamType: MiniOverlayType.liveStream,
      isLive: true,
      isMinimized: false,
    );
    _notifyLegacy();
  }

  /// Toggles or explicitly sets minimized state
  void setMinimized(bool minimized) {
    stateNotifier.value = state.copyWith(isMinimized: minimized);
    _notifyLegacy();
  }

  /// Ends Mini Overlay session and hides overlay
  void endPipSession() {
    stateNotifier.value = state.copyWith(
      isLive: false,
      isMinimized: false,
    );
    _notifyLegacy();
  }
}
