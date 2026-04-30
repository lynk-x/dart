import 'package:equatable/equatable.dart';
import 'package:lynk_core/core.dart';

class ForumSessionsState extends Equatable {
  final List<SessionModel> sessions;
  final bool isLoading;
  final String? errorMessage;

  const ForumSessionsState({
    this.sessions = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  ForumSessionsState copyWith({
    List<SessionModel>? sessions,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ForumSessionsState(
      sessions: sessions ?? this.sessions,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [sessions, isLoading, errorMessage];
}
