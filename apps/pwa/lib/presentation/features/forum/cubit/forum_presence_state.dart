import 'package:equatable/equatable.dart';

class ForumPresenceState extends Equatable {
  final List<Map<String, dynamic>> onlineUsers;
  final bool isTracking;
  final bool isLoading;

  const ForumPresenceState({
    this.onlineUsers = const [],
    this.isTracking = false,
    this.isLoading = false,
  });

  ForumPresenceState copyWith({
    List<Map<String, dynamic>>? onlineUsers,
    bool? isTracking,
    bool? isLoading,
  }) {
    return ForumPresenceState(
      onlineUsers: onlineUsers ?? this.onlineUsers,
      isTracking: isTracking ?? this.isTracking,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [onlineUsers, isTracking, isLoading];
}
