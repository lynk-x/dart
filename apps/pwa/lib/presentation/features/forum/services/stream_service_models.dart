part of 'stream_service.dart';

// Plain data types used by ForumVideoStreamService and its consumers (telemetry, participants,
// stage layout, stream type). A part of the service library, so imports of stream_service.dart
// still expose them unchanged.

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
