import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';

part 'ticket_state.dart';

class TicketCubit extends Cubit<TicketState> {
  TicketCubit() : super(const TicketState());

  RealtimeChannel? _subscription;

  @override
  Future<void> close() {
    _subscription?.unsubscribe();
    return super.close();
  }

  Future<void> loadTicket(String ticketId, {bool isSilent = false}) async {
    if (!isSilent) emit(state.copyWith(isLoading: true, error: null));

    try {
      final response = await Supabase.instance.client.from('tickets').select('''
            *,
            events (
              title,
              location,
              starts_at,
              ends_at,
              media
            ),
            ticket_tiers (
              display_name
            ),
            user_profile:user_id (
              full_name
            )
          ''').eq('id', ticketId).single();

      final userProfile = response['user_profile'] as Map<String, dynamic>?;
      final holderName = userProfile?['full_name'] as String? ?? 'Guest Attendee';

      final ticket = TicketModel.fromMap(response, holderName: holderName);

      emit(state.copyWith(isLoading: false, ticket: ticket));

      // Subscribe to updates if not already listening for this ticket
      if (_subscription == null) {
        _subscribeToUpdates(ticketId);
      }
    } catch (e) {
      if (!isSilent) emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void _subscribeToUpdates(String ticketId) {
    _subscription?.unsubscribe();
    _subscription = Supabase.instance.client
        .channel('ticket_live_status_$ticketId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tickets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: ticketId,
          ),
          callback: (payload) {
            // When the steward scans the QR code, the 'redeemed_at' field is updated.
            // We re-fetch to get the fresh status and nested event data.
            loadTicket(ticketId, isSilent: true);
          },
        )
        .subscribe();
  }

  Future<void> refresh() async {
    if (state.ticket != null) {
      await loadTicket(state.ticket!.id);
    }
  }
}
