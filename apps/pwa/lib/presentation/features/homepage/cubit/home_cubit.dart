import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/data/repositories/repositories.dart';
import 'home_state.dart';

/// Business logic for the Home feed.
///
/// Manages loading, pagination, sorting, and refreshing of [EventModel]s.
/// The UI layer ([HomeView]) only calls methods here and reacts to [HomeState].
class HomeCubit extends Cubit<HomeState> {
  /// How many items to load per page.
  static const int _pageSize = 15;

  final EventRepository _repo;
  final String? Function() _currentUserId;

  /// [userId] defaults to the signed-in Supabase user; tests inject their own.
  HomeCubit(this._repo, {String? Function()? userId})
      : _currentUserId = userId ?? (() => Supabase.instance.client.auth.currentUser?.id),
        super(const HomeState());

  /// A fixed "now" for one feed session. Every page splits events into "not ended" / "ended"
  /// against this instant, so an event that ends between two page fetches is neither returned
  /// twice nor skipped.
  DateTime _anchor = DateTime.now().toUtc();

  /// Bumped by [init]. A [loadMore] that was in flight when the feed was refreshed must not
  /// append its (now stale) page onto the fresh list.
  int _generation = 0;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Loads the first page of events and sets initial state.
  Future<void> init() async {
    final generation = ++_generation;
    _anchor = DateTime.now().toUtc();
    emit(state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      loadMoreFailed: false,
      clearError: true,
    ));
    try {
      final userId = _currentUserId();
      if (userId == null) {
        emit(state.copyWith(isLoading: false));
        return;
      }

      final page = await _fetchPage(userId, past: false);
      if (generation != _generation || isClosed) return;

      emit(state.copyWith(
        events: _sort(page.events),
        isLoading: false,
        hasMore: page.hasMore,
        cursorEndsAt: page.cursorEndsAt,
        cursorForumId: page.cursorForumId,
        clearCursor: page.cursorEndsAt == null,
        showingPast: page.past,
      ));
    } catch (e) {
      if (generation != _generation || isClosed) return;
      emit(state.copyWith(isLoading: false, errorMessage: e.toFriendlyMessage()));
    }
  }

  // ── Pagination ──────────────────────────────────────────────────────────────

  /// Appends the next page of events to the feed.
  ///
  /// Guards against concurrent calls via [HomeState.isLoadingMore], and does nothing after a
  /// failure until [retryLoadMore] is called — otherwise the scroll listener would retry on every
  /// scroll tick.
  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoading || !state.hasMore || state.loadMoreFailed) return;
    final generation = _generation;
    emit(state.copyWith(isLoadingMore: true));
    try {
      final userId = _currentUserId();
      if (userId == null) {
        emit(state.copyWith(isLoadingMore: false));
        return;
      }

      final page = await _fetchPage(
        userId,
        past: state.showingPast,
        afterEndsAt: state.cursorEndsAt,
        afterForumId: state.cursorForumId,
      );
      if (generation != _generation || isClosed) return;

      // Keyset pages shouldn't overlap, but never show an event twice if one slips through.
      final known = state.events.map((e) => e.id).toSet();
      final fresh = page.events.where((e) => !known.contains(e.id)).toList();

      emit(state.copyWith(
        events: _sort([...state.events, ...fresh]),
        isLoadingMore: false,
        hasMore: page.hasMore,
        cursorEndsAt: page.cursorEndsAt,
        cursorForumId: page.cursorForumId,
        showingPast: page.past,
      ));
    } catch (e) {
      if (generation != _generation || isClosed) return;
      emit(state.copyWith(
        isLoadingMore: false,
        loadMoreFailed: true,
        errorMessage: e.toFriendlyMessage(),
      ));
    }
  }

  /// Retries after a failed [loadMore] (the footer's "Retry" action).
  Future<void> retryLoadMore() {
    emit(state.copyWith(loadMoreFailed: false));
    return loadMore();
  }

  // ── Refresh ─────────────────────────────────────────────────────────────────

  /// Clears the existing feed and reloads from the first page.
  Future<void> refresh() => init();

  /// Fetches up to one page starting in the given half of the feed. If the not-ended half runs
  /// out before the page is full it carries on into ended events in the same call — otherwise a
  /// user with only a few upcoming events would get a short list that never scrolls, so the
  /// scroll-triggered [loadMore] would never fire and their past events would never appear.
  Future<_Page> _fetchPage(
    String userId, {
    required bool past,
    String? afterEndsAt,
    String? afterForumId,
  }) async {
    var inPast = past;
    var cursorEnds = afterEndsAt;
    var cursorForum = afterForumId;
    var hasMore = true;
    final rows = <Map<String, dynamic>>[];

    while (true) {
      final remaining = _pageSize - rows.length;
      final batch = await _repo.getUserForums(
        userId,
        limit: remaining,
        past: inPast,
        anchor: _anchor,
        afterEndsAt: cursorEnds,
        afterForumId: cursorForum,
      );
      rows.addAll(batch);
      if (batch.isNotEmpty) {
        cursorEnds = batch.last['event_ends_at'] as String?;
        cursorForum = batch.last['forum_id'] as String?;
      }
      if (batch.length >= remaining) break; // page is full; more may follow in this half
      if (inPast) {
        hasMore = false; // ended events exhausted: that's the end of the feed
        break;
      }
      inPast = true; // not-ended events exhausted: continue into ended ones
      cursorEnds = null;
      cursorForum = null;
    }

    return _Page(
      events: rows.map((json) => EventModel.fromMap(json)).toList(),
      cursorEndsAt: cursorEnds,
      cursorForumId: cursorForum,
      past: inPast,
      hasMore: hasMore,
    );
  }

  // ── Private Helpers ─────────────────────────────────────────────────────────

  /// Sorts [events] by: active first, then those with unread chat, then by
  /// proximity to [DateTime.now] (upcoming before passed, most-recent-past last).
  List<EventModel> _sort(List<EventModel> events) {
    final now = DateTime.now();
    final copy = List<EventModel>.from(events);
    copy.sort((a, b) {
      // 1. Active (not passed) events above completed ones
      if (a.isPassed != b.isPassed) return a.isPassed ? 1 : -1;
      // 2. Unread items bubble to the top within the same group
      if (a.hasUnread != b.hasUnread) return a.hasUnread ? -1 : 1;
      // 3. Closest to now takes precedence
      return a.endDatetime
          .difference(now)
          .abs()
          .compareTo(b.endDatetime.difference(now).abs());
    });
    return copy;
  }

}

/// One fetched page plus where the next one starts.
class _Page {
  final List<EventModel> events;
  final String? cursorEndsAt;
  final String? cursorForumId;
  final bool past;
  final bool hasMore;
  const _Page({
    required this.events,
    required this.cursorEndsAt,
    required this.cursorForumId,
    required this.past,
    required this.hasMore,
  });
}
