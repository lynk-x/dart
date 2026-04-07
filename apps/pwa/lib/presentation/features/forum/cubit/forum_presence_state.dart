import 'package:equatable/equatable.dart';

class ForumPresenceState extends Equatable {
  final List<Map<String, dynamic>> onlineUsers;
  final bool isTracking;

  const ForumPresenceState({
    this.onlineUsers = const [],
    this.isTracking = false,
  });

  ForumPresenceState copyWith({
    List<Map<String, dynamic>>? onlineUsers,
    bool? isTracking,
  }) {
    return ForumPresenceState(
      onlineUsers: onlineUsers ?? this.onlineUsers,
      isTracking: isTracking ?? this.isTracking,
    );
  }

  @override
  List<Object?> get props => [onlineUsers, isTracking];
}
