import 'package:equatable/equatable.dart';
import '../models/call_participant.dart';
import '../widgets/header.dart';

/// Video-call counterpart to [ForumAudioStreamState]. Mirrors it field-for-field
/// except where video has genuinely different state (camera/screen flags
/// replace the audio-only broadcast-mute flag).
class ForumVideoStreamState extends Equatable {
  final bool isLive;
  final ForumHeaderRole role;
  final String? sessionId;

  /// Active call participants, keyed by userId — the source of truth for
  /// who is actually publishing video right now. [activeSpeakerNames]
  /// below is derived from this for the widgets that only ever needed
  /// display names (header text, presence-drawer badges), so those call
  /// sites didn't need to change when this registry was introduced.
  final Map<String, CallParticipant> participants;

  final bool isMicMuted;
  final bool isCameraOn;
  final bool isFrontCamera;
  final bool isScreenSharing;
  final String? errorMessage;

  /// One-shot status line for a snackbar (e.g. "Reconnected"). Like
  /// [errorMessage] it's dropped by the next copyWith, so it shows once.
  final String? infoMessage;
  final String? pendingInviteFromHostName;

  /// True while this user's own publish connection is being replaced
  /// after an ICE failure (see ForumVideoCubit._reconnectVideoPublish).
  /// Host and co-host only — a pure listener never publishes.
  final bool isReconnecting;

  /// True while this LISTENER's own receive-side connection is retrying
  /// after a drop (see service.onRemoteVideoListenerLost's bounded
  /// 3-attempt retry) — distinct from [isReconnecting], which is the
  /// publish side. A user is never both at once (publishing vs.
  /// listening are mutually exclusive roles for the single connection
  /// each cubit instance owns).
  final bool isListenerReconnecting;

  const ForumVideoStreamState({
    this.isLive = false,
    this.role = ForumHeaderRole.listener,
    this.sessionId,
    this.participants = const {},
    this.isMicMuted = true,
    this.isCameraOn = false,
    this.isFrontCamera = true,
    this.isScreenSharing = false,
    this.errorMessage,
    this.infoMessage,
    this.pendingInviteFromHostName,
    this.isReconnecting = false,
    this.isListenerReconnecting = false,
  });

  List<String> get activeSpeakerNames =>
      participants.values.map((s) => s.userName).toList(growable: false);

  ForumVideoStreamState copyWith({
    bool? isLive,
    ForumHeaderRole? role,
    String? sessionId,
    Map<String, CallParticipant>? participants,
    bool? isMicMuted,
    bool? isCameraOn,
    bool? isFrontCamera,
    bool? isScreenSharing,
    bool? isBroadcastMuted,
    String? errorMessage,
    String? infoMessage,
    String? pendingInviteFromHostName,
    bool clearPendingInvite = false,
    bool? isReconnecting,
    bool? isListenerReconnecting,
  }) {
    return ForumVideoStreamState(
      isLive: isLive ?? this.isLive,
      role: role ?? this.role,
      sessionId: sessionId ?? this.sessionId,
      participants: participants ?? this.participants,
      isMicMuted: isMicMuted ?? this.isMicMuted,
      isCameraOn: isCameraOn ?? this.isCameraOn,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      errorMessage: errorMessage,
      infoMessage: infoMessage,
      pendingInviteFromHostName: clearPendingInvite
          ? null
          : (pendingInviteFromHostName ?? this.pendingInviteFromHostName),
      isReconnecting: isReconnecting ?? this.isReconnecting,
      isListenerReconnecting:
          isListenerReconnecting ?? this.isListenerReconnecting,
    );
  }

  @override
  List<Object?> get props => [
        isLive,
        role,
        sessionId,
        participants,
        isMicMuted,
        isCameraOn,
        isFrontCamera,
        isScreenSharing,
        errorMessage,
        infoMessage,
        pendingInviteFromHostName,
        isReconnecting,
        isListenerReconnecting,
      ];
}