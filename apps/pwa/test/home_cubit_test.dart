import 'package:flutter_test/flutter_test.dart';
import 'package:lynk_x/presentation/features/homepage/cubit/home_cubit.dart';
import 'package:lynk_x/presentation/features/homepage/cubit/home_state.dart';
import 'package:lynk_x/data/repositories/event_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

class _FakeEventRepository extends EventRepository {
  _FakeEventRepository() : super(_FakeSupabaseClient());

  @override
  Future<List<Map<String, dynamic>>> getUserForums(String userId,
          {int limit = 15, String? afterStartsAt, String? afterForumId}) async =>
      [];
}

void main() {
  group('HomeCubit', () {
    late HomeCubit cubit;

    setUp(() {
      cubit = HomeCubit(_FakeEventRepository());
    });

    tearDown(() {
      cubit.close();
    });

    test('initial state is empty / not loading', () {
      expect(cubit.state.events, isEmpty);
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.isLoadingMore, isFalse);
      expect(cubit.state.hasMore, isTrue);
      expect(cubit.state.errorMessage, isNull);
    });

    test('init() with no auth user emits isLoading false and empty events',
        () async {
      await cubit.init();
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.events, isEmpty);
    });

    test('loadMore() is a no-op when hasMore is false', () async {
      await cubit.init();
      await cubit.loadMore();
      final countAfterExhaust = cubit.state.events.length;

      await cubit.loadMore();
      expect(cubit.state.events.length, equals(countAfterExhaust));
    });

    test('HomeState.copyWith preserves unchanged fields', () {
      const original = HomeState(isLoading: true, hasMore: false);
      final copy = original.copyWith(isLoadingMore: true);

      expect(copy.isLoading, isTrue);
      expect(copy.hasMore, isFalse);
      expect(copy.isLoadingMore, isTrue);
    });

    test('HomeState.copyWith(clearError: true) removes errorMessage', () {
      const state = HomeState(errorMessage: 'network error');
      final cleared = state.copyWith(clearError: true);
      expect(cleared.errorMessage, isNull);
    });

    test('identical HomeStates are equal', () {
      const a = HomeState();
      const b = HomeState();
      expect(a, equals(b));
    });
  });
}
