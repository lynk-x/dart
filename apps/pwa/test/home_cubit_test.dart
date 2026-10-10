import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynk_x/presentation/features/homepage/cubit/home_cubit.dart';
import 'package:lynk_x/presentation/features/homepage/cubit/home_state.dart';
import 'package:lynk_x/data/repositories/event_repository.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

/// One recorded call to [EventRepository.getUserForums].
class _Call {
  final bool past;
  final int limit;
  final String? afterEndsAt;
  final String? afterForumId;
  _Call(this.past, this.limit, this.afterEndsAt, this.afterForumId);
}

/// Serves rows from two in-memory halves (not ended / ended) the way the real query does:
/// each half is already in display order and filtered by the keyset cursor.
class _FakeEventRepository extends EventRepository {
  _FakeEventRepository({this.upcoming = const [], this.past = const []}) : super(_FakeSupabaseClient());

  final List<Map<String, dynamic>> upcoming;
  final List<Map<String, dynamic>> past;
  final calls = <_Call>[];

  /// Holds the NEXT getUserForums call until the completer is completed — lets a test keep one
  /// fetch "in flight" while others run. Cleared as soon as a call picks it up.
  Completer<void>? holdNextCall;
  Object? failWith;

  @override
  Future<List<Map<String, dynamic>>> getUserForums(
    String userId, {
    int limit = 15,
    required bool past,
    required DateTime anchor,
    String? afterEndsAt,
    String? afterForumId,
  }) async {
    calls.add(_Call(past, limit, afterEndsAt, afterForumId));
    final hold = holdNextCall;
    holdNextCall = null;
    if (hold != null) await hold.future;
    if (failWith != null) throw failWith!;
    final source = past ? this.past : upcoming;
    var start = 0;
    if (afterForumId != null) {
      start = source.indexWhere((r) => r['forum_id'] == afterForumId) + 1;
    }
    return source.skip(start).take(limit).toList();
  }
}

Map<String, dynamic> _row(String id, {required bool past, bool unread = false}) {
  final end = DateTime.now().add(Duration(days: past ? -3 : 3));
  return {
    'forum_id': id,
    'event_id': id,
    'event_title': 'Event $id',
    'event_starts_at': end.subtract(const Duration(hours: 4)).toUtc().toIso8601String(),
    'event_ends_at': end.toUtc().toIso8601String(),
    'has_unread': unread,
    'unread_count': unread ? 7 : 0,
  };
}

List<Map<String, dynamic>> _rows(String prefix, int n, {required bool past}) =>
    List.generate(n, (i) => _row('$prefix${i.toString().padLeft(2, '0')}', past: past));

HomeCubit _cubit(_FakeEventRepository repo, {String? userId = 'user-1'}) =>
    HomeCubit(repo, userId: () => userId);

void main() {
  group('HomeCubit', () {
    test('initial state is empty / not loading', () {
      final cubit = _cubit(_FakeEventRepository());
      expect(cubit.state.events, isEmpty);
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.isLoadingMore, isFalse);
      expect(cubit.state.hasMore, isTrue);
      expect(cubit.state.errorMessage, isNull);
      cubit.close();
    });

    test('init() with no signed-in user stops loading with no events', () async {
      final repo = _FakeEventRepository();
      final cubit = _cubit(repo, userId: null);
      await cubit.init();
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.events, isEmpty);
      expect(repo.calls, isEmpty);
      await cubit.close();
    });

    test('loadMore() is a no-op when hasMore is false', () async {
      final repo = _FakeEventRepository();
      final cubit = _cubit(repo);
      await cubit.init();
      expect(cubit.state.hasMore, isFalse);
      final calls = repo.calls.length;
      await cubit.loadMore();
      expect(repo.calls.length, calls);
      await cubit.close();
    });

    test('HomeState.copyWith preserves unchanged fields', () {
      const original = HomeState(isLoading: true, hasMore: false);
      final copy = original.copyWith(isLoadingMore: true);
      expect(copy.isLoading, isTrue);
      expect(copy.hasMore, isFalse);
      expect(copy.isLoadingMore, isTrue);
    });

    test('not-ended events come first, then ended ones, in server order', () async {
      final repo = _FakeEventRepository(
        upcoming: _rows('u', 3, past: false),
        past: _rows('p', 3, past: true),
      );
      final cubit = _cubit(repo);
      await cubit.init();
      expect(cubit.state.events.map((e) => e.isPassed).toList(),
          [false, false, false, true, true, true]);
      await cubit.close();
    });

    test('a short upcoming list carries on into past events in the same load', () async {
      // 3 upcoming + 20 past: the first call must fill the 15-item page from the past half,
      // otherwise a short list never scrolls and loadMore would never fire.
      final repo = _FakeEventRepository(
        upcoming: _rows('u', 3, past: false),
        past: _rows('p', 20, past: true),
      );
      final cubit = _cubit(repo);
      await cubit.init();
      expect(cubit.state.events.length, 15);
      expect(cubit.state.showingPast, isTrue);
      expect(cubit.state.hasMore, isTrue);
      expect(repo.calls.map((c) => c.past).toList(), [false, true]);
      expect(repo.calls[1].limit, 12);
      await cubit.close();
    });

    test('loadMore continues the past half from the cursor, then ends the feed', () async {
      final repo = _FakeEventRepository(past: _rows('p', 20, past: true));
      final cubit = _cubit(repo);
      await cubit.init();
      expect(cubit.state.events.length, 15);
      expect(cubit.state.hasMore, isTrue);

      await cubit.loadMore();
      expect(cubit.state.events.length, 20);
      expect(cubit.state.hasMore, isFalse);
      expect(cubit.state.events.map((e) => e.id).toSet().length, 20, reason: 'no duplicates');
      await cubit.close();
    });

    test('unread forums (has_unread) bubble to the top of their group', () async {
      final repo = _FakeEventRepository(upcoming: [
        _row('a', past: false),
        _row('b', past: false, unread: true),
      ]);
      final cubit = _cubit(repo);
      await cubit.init();
      expect(cubit.state.events.first.id, 'b');
      expect(cubit.state.events.first.hasUnread, isTrue);
      await cubit.close();
    });

    test('no event id is pinned: order follows the ordinary rules only', () async {
      // The id that used to be hard-coded to the top now sorts like any other event: the later
      // ending one comes after the sooner ending one.
      final soon = _row('soon', past: false);
      final later = _row('afrofest-2026', past: false)
        ..['event_ends_at'] = DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String();
      final repo = _FakeEventRepository(upcoming: [later, soon]);
      final cubit = _cubit(repo);
      await cubit.init();
      expect(cubit.state.events.map((e) => e.id).toList(), ['soon', 'afrofest-2026']);
      await cubit.close();
    });

    test('refresh during an in-flight loadMore discards the stale page', () async {
      final repo = _FakeEventRepository(past: _rows('p', 20, past: true));
      final cubit = _cubit(repo);
      await cubit.init();
      expect(cubit.state.events.length, 15);

      // loadMore starts and parks inside the repository...
      final release = Completer<void>();
      repo.holdNextCall = release;
      final stale = cubit.loadMore();
      await Future<void>.delayed(Duration.zero);

      // ...the user pulls to refresh and that completes first...
      await cubit.refresh();
      expect(cubit.state.events.length, 15);

      // ...then the old request finally returns. Its page must not land on the fresh feed.
      release.complete();
      await stale;
      expect(cubit.state.events.length, 15);
      expect(cubit.state.isLoadingMore, isFalse);
      await cubit.close();
    });

    test('a failed loadMore does not retry on its own, but retryLoadMore does', () async {
      final repo = _FakeEventRepository(past: _rows('p', 20, past: true));
      final cubit = _cubit(repo);
      await cubit.init();

      repo.failWith = Exception('offline');
      await cubit.loadMore();
      expect(cubit.state.loadMoreFailed, isTrue);
      expect(cubit.state.isLoadingMore, isFalse);

      final callsAfterFailure = repo.calls.length;
      await cubit.loadMore(); // e.g. the scroll listener firing again
      await cubit.loadMore();
      expect(repo.calls.length, callsAfterFailure, reason: 'no automatic retries');

      repo.failWith = null;
      await cubit.retryLoadMore();
      expect(cubit.state.loadMoreFailed, isFalse);
      expect(cubit.state.events.length, 20);
      await cubit.close();
    });

    test('EventModel reads the real unread_count of v1_user_forums', () {
      final unread = EventModel.fromMap(_row('x', past: false, unread: true));
      expect(unread.chatCount, 7);
      expect(unread.hasUnread, isTrue);
      final read = EventModel.fromMap(_row('y', past: false));
      expect(read.chatCount, 0);
      expect(read.hasUnread, isFalse);
    });

    test('EventModel falls back to the boolean flag when no count is present', () {
      final row = _row('z', past: false, unread: true)..remove('unread_count');
      expect(EventModel.fromMap(row).chatCount, 1);
    });
  });
}
