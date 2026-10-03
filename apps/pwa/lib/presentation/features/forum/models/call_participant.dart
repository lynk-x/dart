import 'package:equatable/equatable.dart';

/// One active participant in a multi-speaker call — the client-side mirror
/// of a social.forum_call_participants row (active rows only, left_at IS
/// NULL). Listeners bootstrap a registry of these from
/// api.v1_forum_call_participants on join, then keep it current via
/// incremental participant_joined/participant_left broadcast events — see
/// ForumAudioStreamCubit/ForumVideoStage's registry handling.
class CallParticipant extends Equatable {
  final String userId;
  final String userName;
  final String cfSessionId;
  final String trackName;

  const CallParticipant({
    required this.userId,
    required this.userName,
    required this.cfSessionId,
    required this.trackName,
  });

  factory CallParticipant.fromJson(Map<String, dynamic> json) {
    return CallParticipant(
      userId: json['userId'] as String? ?? json['user_id'] as String? ?? '',
      userName: json['userName'] as String? ??
          json['user_name'] as String? ??
          json['full_name'] as String? ??
          'Speaker',
      cfSessionId: json['cfSessionId'] as String? ??
          json['cf_session_id'] as String? ??
          '',
      trackName: json['trackName'] as String? ?? json['track_name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toBroadcastPayload() => {
        'userId': userId,
        'userName': userName,
        'cfSessionId': cfSessionId,
        'trackName': trackName,
      };

  @override
  List<Object?> get props => [userId, userName, cfSessionId, trackName];
}
