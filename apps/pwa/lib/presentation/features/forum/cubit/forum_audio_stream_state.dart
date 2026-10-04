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

  /// True while this user's own publish connection is being replaced
  /// after an ICE failure (see ForumAudioStreamCubit._reconnectPublish).
  /// Host and co-host only — a pure listener never publishes.
  final bool isReconnecting;

  /// True while this LISTENER's own receive-side connection is retrying
  /// after a drop (see service.onRemoteAudioListenerLost's bounded
  /// 3-attempt retry) — distinct from [isReconnecting], which is the
  /// publish side. A user is never both at once (publishing vs.
  /// listening are mutually exclusive roles for the single connection
  /// each cubit instance owns).
  final bool isListenerReconnecting;

  const ForumAudioStreamState({
    this.isLive = false,
    this.role = ForumHeaderRole.listener,
    this.sessionId,
    this.participants = const {},
    this.isMicMuted = true,
    this.isBroadcastMuted = false,
    this.errorMessage,
    this.pendingInviteFromHostName,
    this.isReconnecting = false,
    this.isListenerReconnecting = false,
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
    bool? isReconnecting,
    bool? isListenerReconnecting,
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
      isReconnecting: isReconnecting ?? this.isReconnecting,
      isListenerReconnecting: isListenerReconnecting ?? this.isListenerReconnecting,
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
        isReconnecting,
        isListenerReconnecting,
      ];
}
