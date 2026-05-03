import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/data/repositories/repositories.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';

part 'ticket_state.dart';

class TicketCubit extends Cubit<TicketState> {
  final TicketRepository _repo;
  TicketCubit(this._repo) : super(const TicketState());

  RealtimeChannel? _subscription;

  @override
  Future<void> close() {
    _subscription?.unsubscribe();
    return super.close();
  }

  Future<void> loadTicket(String ticketId, {bool isSilent = false}) async {
    if (!isSilent) emit(state.copyWith(isLoading: true, error: null));

    try {
      // 1. Fetch ticket data from view
      final response = await Supabase.instance.client
          .from('vw_user_tickets')
          .select()
          .eq('ticket_id', ticketId)
          .single();

      final ticket = TicketModel.fromView(response);

      // 2. Fetch pending listings separately (as joins on views can be complex for PostgREST)
      final listingsResponse = await Supabase.instance.client
          .from('ticket_listings')
          .select('id, status, asking_price, currency, buyer_id, expires_at')
          .eq('ticket_id', ticketId)
          .eq('status', 'pending');

      final pendingListing = (listingsResponse as List).cast<Map<String, dynamic>>().firstOrNull;

      emit(state.copyWith(
        isLoading: false,
        ticket: ticket,
        pendingListing: pendingListing,
        clearPendingListing: pendingListing == null,
      ));

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
    // tickets.tickets is in the `tickets` schema, not `public`. The table must
    // also be on the supabase_realtime publication for this subscription to fire.
    _subscription = _repo.subscribeToTicket(ticketId, (payload) {
          // When the steward scans the QR code, `redeemed_at` is updated.
          // Re-fetch via the view to get the fresh status and nested event data.
          loadTicket(ticketId, isSilent: true);
        })
        .subscribe();
  }

  Future<void> refresh() async {
    if (state.ticket != null) {
      await loadTicket(state.ticket!.id);
    }
  }

  Future<String> createResaleListing({
    required String recipientUsername,
    required double askingPrice,
  }) async {
    final ticketId = state.ticket?.id;
    if (ticketId == null) throw Exception('No ticket loaded');

    final result = await Supabase.instance.client.rpc(
      'create_ticket_listing',
      params: {
        'p_ticket_id': ticketId,
        'p_recipient_username': recipientUsername,
        'p_asking_price': askingPrice,
      },
    );
    await loadTicket(ticketId, isSilent: true);
    return result as String;
  }

  Future<void> cancelResaleListing(String listingId) async {
    await Supabase.instance.client.rpc(
      'cancel_ticket_listing',
      params: {'p_listing_id': listingId},
    );
    if (state.ticket != null) {
      await loadTicket(state.ticket!.id, isSilent: true);
    }
  }
}
