import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/data/repositories/repositories.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';
import 'package:lynk_x/presentation/features/ticket/utils/ticket_cache.dart';

class TicketsListState {
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final List<TicketModel> tickets;
  final String? error;

  /// Keyset cursor: (created_at, ticket_id) of the last row from the most
  /// recent fetch. Null until the first page has loaded.
  final String? cursorCreatedAt;
  final String? cursorTicketId;

  const TicketsListState({
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.tickets = const [],
    this.error,
    this.cursorCreatedAt,
    this.cursorTicketId,
  });

  TicketsListState copyWith({
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    List<TicketModel>? tickets,
    String? error,
    String? cursorCreatedAt,
    String? cursorTicketId,
  }) {
    return TicketsListState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      tickets: tickets ?? this.tickets,
      error: error,
      cursorCreatedAt: cursorCreatedAt ?? this.cursorCreatedAt,
      cursorTicketId: cursorTicketId ?? this.cursorTicketId,
    );
  }
}

class TicketsListCubit extends Cubit<TicketsListState> {
  final TicketRepository _repo;
  final TicketCache _cache;

  TicketsListCubit(this._repo, [this._cache = const TicketCache()])
      : super(const TicketsListState());

  /// Page size mirrors home_cubit and other paginated lists in the app.
  static const int _pageSize = 20;

  Future<void> loadTickets() async {
    // 1. Instant offline cache load
    final cached = await _cache.loadTickets();
    if (cached != null && cached.isNotEmpty) {
      emit(state.copyWith(isLoading: false, tickets: cached));
    } else {
      emit(TicketsListState(isLoading: true));
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (state.tickets.isEmpty) {
          emit(state.copyWith(isLoading: false, error: 'User not logged in'));
        }
        return;
      }

      final rawTickets = await _repo.getUserTickets(
        user.id,
        limit: _pageSize,
      );

      final tickets = rawTickets
          .map((data) => TicketModel.fromView(data))
          .toList();
      final last = rawTickets.isNotEmpty ? rawTickets.last : null;

      // 2. Persist fresh tickets to offline cache
      await _cache.saveTickets(tickets);

      emit(state.copyWith(
        isLoading: false,
        tickets: tickets,
        error: null,
        hasMore: tickets.length == _pageSize,
        cursorCreatedAt: last?['created_at'] as String?,
        cursorTicketId: last?['ticket_id'] as String?,
      ));
    } catch (e) {
      // 3. If cached tickets exist, preserve offline view gracefully
      if (state.tickets.isEmpty) {
        emit(state.copyWith(isLoading: false, error: e.toString()));
      } else {
        emit(state.copyWith(isLoading: false));
      }
    }
  }

  /// Appends the next page of tickets. Guards against concurrent calls and
  /// signals end-of-list via `hasMore: false` when a partial page comes back.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    emit(state.copyWith(isLoadingMore: true));
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        emit(state.copyWith(isLoadingMore: false, error: 'User not logged in'));
        return;
      }

      final rawMore = await _repo.getUserTickets(
        user.id,
        limit: _pageSize,
        beforeCreatedAt: state.cursorCreatedAt,
        beforeTicketId: state.cursorTicketId,
      );

      final more = rawMore
          .map((data) => TicketModel.fromView(data))
          .toList();

      if (rawMore.isEmpty) {
        emit(state.copyWith(isLoadingMore: false, hasMore: false));
      } else {
        final last = rawMore.last;
        emit(state.copyWith(
          isLoadingMore: false,
          tickets: [...state.tickets, ...more],
          hasMore: more.length == _pageSize,
          cursorCreatedAt: last['created_at'] as String?,
          cursorTicketId: last['ticket_id'] as String?,
        ));
      }
    } catch (e) {
      emit(state.copyWith(isLoadingMore: false, error: e.toString()));
    }
  }

  Future<void> refresh() => loadTickets();
}
