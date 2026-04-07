import 'package:equatable/equatable.dart';
import 'package:lynk_core/core.dart';

/// Immutable state for the home feed managed by [HomeCubit].
class HomeState extends Equatable {
  /// The full sorted list of events displayed in the feed.
  final List<EventModel> events;

  /// True when the initial page load is in progress (shows a full-screen loader).
  final bool isLoading;

  /// True when an incremental page is being appended (shows a bottom spinner).
  final bool isLoadingMore;

  /// False when all available pages have been loaded; prevents further fetches.
  final bool hasMore;

  /// Non-null when a Supabase or network error occurs during a fetch.
  final String? errorMessage;

  const HomeState({
    this.events = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.errorMessage,
  });

  HomeState copyWith({
    List<EventModel>? events,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? errorMessage,
    bool clearError = false,
  }) {
    return HomeState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props =>
      [events, isLoading, isLoadingMore, hasMore, errorMessage];
}
