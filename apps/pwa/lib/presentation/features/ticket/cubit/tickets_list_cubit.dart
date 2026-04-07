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

      // 1. Get profile for holder name
      final profileResponse = await Supabase.instance.client
          .from('user_profiles')
          .select('full_name')
          .eq('user_id', user.id)
          .single();
      
      final holderName = profileResponse['full_name'] as String? ?? 'Me';

      // 2. Get tickets with joined event and tier data
      final response = await Supabase.instance.client.from('tickets').select('''
            *,
            events (
              title,
              location_name,
              starts_at,
              ends_at,
              thumbnail_url
            ),
            ticket_tiers (
              display_name
            )
          ''').eq('user_id', user.id).order('created_at', ascending: false);

      final tickets = (response as List).map((data) {
        return TicketModel.fromMap(data as Map<String, dynamic>, holderName: holderName);
      }).toList();

      emit(state.copyWith(isLoading: false, tickets: tickets));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> refresh() => loadTickets();
}
