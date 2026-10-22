import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynk_x/presentation/features/ticket/cubit/tickets_list_cubit.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';
import 'package:lynk_x/presentation/features/ticket/utils/ticket_cache.dart';
import 'package:lynk_x/data/repositories/ticket_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockTicketRepository extends Mock implements TicketRepository {}
class MockTicketCache extends Mock implements TicketCache {}
class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TicketsListCubit', () {
    late MockTicketRepository repo;
    late MockTicketCache cache;

    setUp(() {
      repo = MockTicketRepository();
      cache = MockTicketCache();
    });

    test('initial state is correct', () {
      final cubit = TicketsListCubit(repo, cache);
      expect(cubit.state.isLoading, false);
      expect(cubit.state.tickets, isEmpty);
      expect(cubit.state.hasMore, true);
      cubit.close();
    });

    blocTest<TicketsListCubit, TicketsListState>(
      'loadTickets emits loading then loaded with tickets',
      build: () {
        when(() => cache.loadTickets()).thenAnswer((_) async => null);
        when(() => repo.getUserTickets(any(), limit: any(named: 'limit')))
            .thenAnswer((_) async => []);
        return TicketsListCubit(repo, cache);
      },
      act: (cubit) => cubit.loadTickets(),
      expect: () => [
        isA<TicketsListState>().having((s) => s.isLoading, 'isLoading', true),
        isA<TicketsListState>()
            .having((s) => s.isLoading, 'isLoading', false)
            .having((s) => s.tickets, 'tickets', isEmpty),
      ],
    );

    blocTest<TicketsListCubit, TicketsListState>(
      'loadMore does nothing if already loading',
      build: () {
        when(() => cache.loadTickets()).thenAnswer((_) async => null);
        when(() => repo.getUserTickets(any(), limit: any(named: 'limit')))
            .thenAnswer((_) async => []);
        return TicketsListCubit(repo, cache);
      },
      act: (cubit) async {
        await cubit.loadTickets();
        await cubit.loadMore();
      },
      expect: () => [
        isA<TicketsListState>().having((s) => s.isLoading, 'isLoading', true),
        isA<TicketsListState>()
            .having((s) => s.isLoading, 'isLoading', false),
      ],
    );
  });
}
