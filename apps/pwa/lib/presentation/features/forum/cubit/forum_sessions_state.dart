import 'package:equatable/equatable.dart';
import 'package:lynk_core/core.dart';

class ForumSessionsState extends Equatable {
  final List<SessionModel> sessions;
  final bool isLoading;
  final String? errorMessage;
  final DateTime? eventStartsAt;
  final DateTime? eventEndsAt;

  const ForumSessionsState({
    this.sessions = const [],
    this.isLoading = false,
    this.errorMessage,
    this.eventStartsAt,
    this.eventEndsAt,
  });

  ForumSessionsState copyWith({
    List<SessionModel>? sessions,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    DateTime? eventStartsAt,
    DateTime? eventEndsAt,
  }) {
    return ForumSessionsState(
      sessions: sessions ?? this.sessions,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      eventStartsAt: eventStartsAt ?? this.eventStartsAt,
      eventEndsAt: eventEndsAt ?? this.eventEndsAt,
    );
  }

  @override
  List<Object?> get props => [sessions, isLoading, errorMessage, eventStartsAt, eventEndsAt];
}
