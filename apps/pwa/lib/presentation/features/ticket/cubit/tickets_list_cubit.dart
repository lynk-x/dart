import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/data/repositories/repositories.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';

class TicketsListState {
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final List<TicketModel> tickets;
  final String? error;

  const TicketsListState({
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.tickets = const [],
    this.error,
  });

  TicketsListState copyWith({
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    List<TicketModel>? tickets,
    String? error,
  }) {
    return TicketsListState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      tickets: tickets ?? this.tickets,
      error: error,
    );
  }
}

class TicketsListCubit extends Cubit<TicketsListState> {
  final TicketRepository _repo;
  TicketsListCubit(this._repo) : super(const TicketsListState());

  /// Page size mirrors home_cubit and other paginated lists in the app.
  static const int _pageSize = 20;

  Future<void> loadTickets() async {
    emit(state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      hasMore: true,
      tickets: const [],
      error: null,
    ));
    try {


      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        emit(state.copyWith(isLoading: false, error: 'User not logged in'));
        return;
      }

      final rawTickets = await _repo.getUserTickets(
        user.id,
        limit: _pageSize,
        offset: 0,
      );

      final tickets = rawTickets
          .map((data) => TicketModel.fromView(data))
          .toList();

      emit(state.copyWith(
        isLoading: false,
        tickets: tickets,
        hasMore: tickets.length == _pageSize,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
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
        offset: state.tickets.length,
      );

      final more = rawMore
          .map((data) => TicketModel.fromView(data))
          .toList();

      emit(state.copyWith(
        isLoadingMore: false,
        tickets: [...state.tickets, ...more],
        hasMore: more.length == _pageSize,
      ));
    } catch (e) {
      emit(state.copyWith(isLoadingMore: false, error: e.toString()));
    }
  }

  Future<void> refresh() => loadTickets();
}
