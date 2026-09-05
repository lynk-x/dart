import 'package:equatable/equatable.dart';
import '../widgets/header.dart';

class ForumAudioStreamState extends Equatable {
  final bool isLive;
  final ForumHeaderRole role;
  final String? sessionId;
  final List<String> activeSpeakerNames;
  final bool isMicMuted;
  final bool isBroadcastMuted;
  final String? errorMessage;

  const ForumAudioStreamState({
    this.isLive = false,
    this.role = ForumHeaderRole.listener,
    this.sessionId,
    this.activeSpeakerNames = const [],
    this.isMicMuted = true,
    this.isBroadcastMuted = false,
    this.errorMessage,
  });

  ForumAudioStreamState copyWith({
    bool? isLive,
    ForumHeaderRole? role,
    String? sessionId,
    List<String>? activeSpeakerNames,
    bool? isMicMuted,
    bool? isBroadcastMuted,
    String? errorMessage,
  }) {
    return ForumAudioStreamState(
      isLive: isLive ?? this.isLive,
      role: role ?? this.role,
      sessionId: sessionId ?? this.sessionId,
      activeSpeakerNames: activeSpeakerNames ?? this.activeSpeakerNames,
      isMicMuted: isMicMuted ?? this.isMicMuted,
      isBroadcastMuted: isBroadcastMuted ?? this.isBroadcastMuted,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        isLive,
        role,
        sessionId,
        activeSpeakerNames,
        isMicMuted,
        isBroadcastMuted,
        errorMessage,
      ];
}
