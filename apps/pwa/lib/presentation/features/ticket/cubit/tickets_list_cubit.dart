import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';

class TicketsListState {
  final bool isLoading;
  final List<TicketModel> tickets;
  final String? error;

  const TicketsListState({
    this.isLoading = false,
    this.tickets = const [],
    this.error,
  });

  TicketsListState copyWith({
    bool? isLoading,
    List<TicketModel>? tickets,
    String? error,
  }) {
    return TicketsListState(
      isLoading: isLoading ?? this.isLoading,
      tickets: tickets ?? this.tickets,
      error: error,
    );
  }
}

class TicketsListCubit extends Cubit<TicketsListState> {
  TicketsListCubit() : super(const TicketsListState());

  Future<void> loadTickets() async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        emit(state.copyWith(isLoading: false, error: 'User not logged in'));
        return;
      }

      // Use vw_user_tickets view which is pre-joined and RLS-protected
      final response = await Supabase.instance.client
          .from('vw_user_tickets')
          .select()
          .order('purchased_at', ascending: false);

      final tickets = (response as List).map((data) {
        return TicketModel.fromView(data as Map<String, dynamic>);
      }).toList();

      emit(state.copyWith(isLoading: false, tickets: tickets));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> refresh() => loadTickets();
}
