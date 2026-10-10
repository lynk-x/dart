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

  /// True when the last attempt to append a page failed. Scrolling no longer retries on its own
  /// (that would hammer a failing connection on every scroll tick); the footer offers a retry.
  final bool loadMoreFailed;

  /// False when all available pages have been loaded; prevents further fetches.
  final bool hasMore;

  /// Non-null when a Supabase or network error occurs during a fetch.
  final String? errorMessage;

  /// Keyset cursor: (event_ends_at, forum_id) of the last row from the most recent fetch. Null
  /// until the first page has loaded.
  final String? cursorEndsAt;
  final String? cursorForumId;

  /// True once the feed has moved on from events that haven't ended to ended ones — the cursor
  /// above then belongs to the ended half.
  final bool showingPast;

  const HomeState({
    this.events = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
    this.hasMore = true,
    this.errorMessage,
    this.cursorEndsAt,
    this.cursorForumId,
    this.showingPast = false,
  });

  HomeState copyWith({
    List<EventModel>? events,
    bool? isLoading,
    bool? isLoadingMore,
    bool? loadMoreFailed,
    bool? hasMore,
    String? errorMessage,
    bool clearError = false,
    String? cursorEndsAt,
    String? cursorForumId,
    bool clearCursor = false,
    bool? showingPast,
  }) {
    return HomeState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      cursorEndsAt: clearCursor ? null : cursorEndsAt ?? this.cursorEndsAt,
      cursorForumId: clearCursor ? null : cursorForumId ?? this.cursorForumId,
      showingPast: showingPast ?? this.showingPast,
    );
  }

  @override
  List<Object?> get props => [
        events,
        isLoading,
        isLoadingMore,
        loadMoreFailed,
        hasMore,
        errorMessage,
        cursorEndsAt,
        cursorForumId,
        showingPast,
      ];
}
