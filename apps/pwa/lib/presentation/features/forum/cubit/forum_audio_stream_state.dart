import 'package:equatable/equatable.dart';
import '../models/call_participant.dart';
import '../widgets/header.dart';

class ForumAudioStreamState extends Equatable {
  final bool isLive;
  final ForumHeaderRole role;
  final String? sessionId;

  /// Active call participants, keyed by userId — the source of truth for
  /// who is actually publishing audio right now. [activeSpeakerNames]
  /// below is derived from this for the widgets that only ever needed
  /// display names (header text, presence-drawer badges), so those call
  /// sites didn't need to change when this registry was introduced.
  final Map<String, CallParticipant> participants;

  final bool isMicMuted;
  final bool isBroadcastMuted;
  final String? errorMessage;
  final String? pendingInviteFromHostName;

  const ForumAudioStreamState({
    this.isLive = false,
    this.role = ForumHeaderRole.listener,
    this.sessionId,
    this.participants = const {},
    this.isMicMuted = true,
    this.isBroadcastMuted = false,
    this.errorMessage,
    this.pendingInviteFromHostName,
  });

  List<String> get activeSpeakerNames =>
      participants.values.map((s) => s.userName).toList(growable: false);

  ForumAudioStreamState copyWith({
    bool? isLive,
    ForumHeaderRole? role,
    String? sessionId,
    Map<String, CallParticipant>? participants,
    bool? isMicMuted,
    bool? isBroadcastMuted,
    String? errorMessage,
    String? pendingInviteFromHostName,
    bool clearPendingInvite = false,
  }) {
    return ForumAudioStreamState(
      isLive: isLive ?? this.isLive,
      role: role ?? this.role,
      sessionId: sessionId ?? this.sessionId,
      participants: participants ?? this.participants,
      isMicMuted: isMicMuted ?? this.isMicMuted,
      isBroadcastMuted: isBroadcastMuted ?? this.isBroadcastMuted,
      errorMessage: errorMessage,
      pendingInviteFromHostName: clearPendingInvite
          ? null
          : (pendingInviteFromHostName ?? this.pendingInviteFromHostName),
    );
  }

  @override
  List<Object?> get props => [
        isLive,
        role,
        sessionId,
        participants,
        isMicMuted,
        isBroadcastMuted,
        errorMessage,
        pendingInviteFromHostName,
      ];
}
