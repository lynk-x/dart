import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/presentation/features/homepage/models/home_model.dart';
import 'home_state.dart';

/// Business logic for the Home feed.
///
/// Manages loading, pagination, sorting, and refreshing of [EventModel]s.
/// The UI layer ([HomeView]) only calls methods here and reacts to [HomeState].
///
/// **Data source:** Mock data for now. Future work: swap [_generateMockEvents]
/// for a real Supabase query once auth credentials are configured.
class HomeCubit extends Cubit<HomeState> {
  /// How many items to load per page.
  static const int _pageSize = 15;

  HomeCubit() : super(const HomeState());

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Loads the first page of events and sets initial state.
  Future<void> init() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) {
        emit(state.copyWith(isLoading: false));
        return;
      }

      final data = await Supabase.instance.client
          .from('vw_user_forums')
          .select()
          .eq('user_id', currentUserId)
          .order('event_starts_at', ascending: true)
          .limit(_pageSize);

      final events = data.map((json) => EventModel.fromMap(json)).toList();

      emit(state.copyWith(
        events: _sort(events),
        isLoading: false,
        hasMore: events.length >= _pageSize,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  // ── Pagination ──────────────────────────────────────────────────────────────

  /// Appends the next page of events to the feed.
  ///
  /// Guards against concurrent calls via [HomeState.isLoadingMore].
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    emit(state.copyWith(isLoadingMore: true));
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) {
        emit(state.copyWith(isLoadingMore: false));
        return;
      }

      final startIndex = state.events.length;
      final data = await Supabase.instance.client
          .from('vw_user_forums')
          .select()
          .eq('user_id', currentUserId)
          .order('event_starts_at', ascending: true)
          .range(startIndex, startIndex + _pageSize - 1);

      final more = data.map((json) => EventModel.fromMap(json)).toList();

      if (more.isEmpty) {
        emit(state.copyWith(isLoadingMore: false, hasMore: false));
      } else {
        emit(state.copyWith(
          events: _sort([...state.events, ...more]),
          isLoadingMore: false,
          hasMore: more.length >= _pageSize,
        ));
      }
    } catch (e) {
      emit(state.copyWith(isLoadingMore: false, errorMessage: e.toString()));
    }
  }

  // ── Refresh ─────────────────────────────────────────────────────────────────

  /// Clears the existing feed and reloads from the first page.
  Future<void> refresh() => init();

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
      return a.startDatetime
          .difference(now)
          .abs()
          .compareTo(b.startDatetime.difference(now).abs());
    });
    return copy;
  }

  // _generateMockEvents removed during Supabase integration
}
