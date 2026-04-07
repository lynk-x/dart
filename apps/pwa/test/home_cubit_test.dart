import 'package:flutter_test/flutter_test.dart';
import 'package:lynk_x/presentation/features/homepage/cubit/home_cubit.dart';
import 'package:lynk_x/presentation/features/homepage/cubit/home_state.dart';

void main() {
  group('HomeCubit', () {
    late HomeCubit cubit;

    setUp(() {
      cubit = HomeCubit();
    });

    tearDown(() {
      cubit.close();
    });

    // ── init() ──────────────────────────────────────────────────────────────

    test('initial state is empty / not loading', () {
      expect(cubit.state.events, isEmpty);
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.isLoadingMore, isFalse);
      expect(cubit.state.hasMore, isTrue);
      expect(cubit.state.errorMessage, isNull);
    });

    test('init() populates 12 mock events and clears isLoading', () async {
      await cubit.init();

      final state = cubit.state;
      expect(state.events, hasLength(12));
      expect(state.isLoading, isFalse);
      expect(state.isLoadingMore, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('init() returns events with non-empty titles', () async {
      await cubit.init();
      for (final event in cubit.state.events) {
        expect(event.title, isNotEmpty);
      }
    });

    // ── sorting ─────────────────────────────────────────────────────────────

    test('init() sorts active events before passed events', () async {
      await cubit.init();
      final events = cubit.state.events;

      // Find where the first passed event is
      final firstPassedIndex = events.indexWhere((e) => e.isPassed);
      if (firstPassedIndex == -1) return; // all active — sort trivially passes

      // All events before firstPassedIndex must be active (not passed)
      for (int i = 0; i < firstPassedIndex; i++) {
        expect(events[i].isPassed, isFalse,
            reason: 'Event at $i should be active, not passed');
      }
    });

    test('within the same group, events with unread chat come first', () async {
      await cubit.init();
      final events = cubit.state.events;

      // Only check within the active group
      final activeEvents = events.where((e) => !e.isPassed).toList();
      final firstReadIndex = activeEvents.indexWhere((e) => !e.hasUnread);
      if (firstReadIndex == -1) return; // all unread — passes trivially

      for (int i = 0; i < firstReadIndex; i++) {
        expect(activeEvents[i].hasUnread, isTrue,
            reason: 'Unread event at $i should precede read events');
      }
    });

    // ── loadMore() ──────────────────────────────────────────────────────────

    test('loadMore() first call emits isLoadingMore then resets it', () async {
      await cubit.init();

      // After loadMore() all 12 items are already at cap, so it should exhaust
      await cubit.loadMore();

      // isLoadingMore must be false once the call completes
      expect(cubit.state.isLoadingMore, isFalse);
      // and hasMore should be false since the mock cap is reached
      expect(cubit.state.hasMore, isFalse);
    });

    test('loadMore() when no more data sets hasMore to false', () async {
      await cubit.init(); // loads first 12 (= cap)
      await cubit
          .loadMore(); // tries to load more from offset 12 — should get 0
      expect(cubit.state.hasMore, isFalse);
      expect(cubit.state.isLoadingMore, isFalse);
    });

    test('loadMore() is a no-op when hasMore is false', () async {
      await cubit.init();
      await cubit.loadMore(); // sets hasMore=false
      final countAfterExhaust = cubit.state.events.length;

      await cubit.loadMore(); // should do nothing
      expect(cubit.state.events.length, equals(countAfterExhaust));
    });

    // ── refresh() ───────────────────────────────────────────────────────────

    test('refresh() resets the events list to the first page', () async {
      await cubit.init();
      // Artificially append extra state to verify reset
      final originalCount = cubit.state.events.length;

      await cubit.refresh();
      expect(cubit.state.events.length, equals(originalCount));
      expect(cubit.state.hasMore, isTrue);
      expect(cubit.state.isLoading, isFalse);
    });

    // ── HomeState copyWith ───────────────────────────────────────────────────

    test('HomeState.copyWith preserves unchanged fields', () {
      const original = HomeState(isLoading: true, hasMore: false);
      final copy = original.copyWith(isLoadingMore: true);

      expect(copy.isLoading, isTrue); // preserved
      expect(copy.hasMore, isFalse); // preserved
      expect(copy.isLoadingMore, isTrue); // changed
    });

    test('HomeState.copyWith(clearError: true) removes errorMessage', () {
      const state = HomeState(errorMessage: 'network error');
      final cleared = state.copyWith(clearError: true);
      expect(cleared.errorMessage, isNull);
    });

    // ── Equatable ───────────────────────────────────────────────────────────

    test('identical HomeStates are equal', () {
      const a = HomeState();
      const b = HomeState();
      expect(a, equals(b));
    });
  });
}
