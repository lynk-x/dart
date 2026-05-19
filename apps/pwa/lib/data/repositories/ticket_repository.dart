import 'package:supabase_flutter/supabase_flutter.dart';

class TicketRepository {
  final SupabaseClient _client;
  TicketRepository(this._client);

  Future<List<Map<String, dynamic>>> getUserTickets(
    String userId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final data = await _client
        .schema('api')
        .from('v1_user_tickets')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>?> getTicketById(String ticketId) async {
    return await _client
        .schema('api')
        .from('v1_user_tickets')
        .select()
        .eq('ticket_id', ticketId)
        .maybeSingle();
  }

  Future<void> transferTicket(String ticketId, String toUserId) async {
    await _client.rpc('transfer_ticket', params: {
      'p_ticket_id': ticketId,
      'p_to_user_id': toUserId,
    });
  }

  Future<List<Map<String, dynamic>>> getTicketTiers(String eventId) async {
    final data = await _client
        .schema('api')
        .from('v1_ticket_tiers')
        .select('id, event_id, display_name, description, price, capacity, tickets_sold, tickets_available, min_per_order, max_per_order, sales_start, sales_end, info')
        .eq('event_id', eventId)
        .order('price', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  /// Atomically reserves [quantity] tickets for [tierId].
  /// Returns the reservation UUID — valid for 15 minutes.
  Future<String> lockForCheckout(String tierId, int quantity) async {
    final result = await _client.rpc('lock_tickets_for_checkout', params: {
      'p_tier_id': tierId,
      'p_quantity': quantity,
    });
    return result as String;
  }

  /// Purchases tickets using an existing reservation.
  /// Returns the full RPC response: { ticket_ids, amount, currency }.
  Future<Map<String, dynamic>> purchaseTickets({
    required String eventId,
    required String tierId,
    required int quantity,
    required String reservationId,
    String provider = 'in-app',
    String? promoCode,
  }) async {
    final result = await _client.rpc('purchase_tickets', params: {
      'p_event_id': eventId,
      'p_tier_id': tierId,
      'p_quantity': quantity,
      'p_provider': provider,
      'p_reservation_id': reservationId,
      if (promoCode != null) 'p_promo_code': promoCode,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>?> getActiveReservation(String userId, String tierId) async {
    return await _client
        .schema('api')
        .from('v1_ticket_reservations')
        .select()
        .eq('user_id', userId)
        .eq('ticket_tier_id', tierId)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .maybeSingle();
  }

  RealtimeChannel subscribeToTicket(
    String ticketId,
    void Function(PostgresChangePayload) callback,
  ) {
    return _client
        .channel('ticket_live_status_$ticketId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'ticketing',
          table: 'tickets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: ticketId,
          ),
          callback: callback,
        );
  }

  RealtimeChannel subscribeToTicketListing(
    String ticketId,
    void Function(PostgresChangePayload) callback,
  ) {
    return _client
        .channel('ticket_listings:$ticketId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ticket_listings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: ticketId,
          ),
          callback: callback,
        );
  }

  Future<Map<String, dynamic>?> getPendingListing(String ticketId) async {
    final listingsResponse = await _client
        .from('ticket_listings')
        .select('id, status, asking_price, currency, buyer_id, expires_at')
        .eq('ticket_id', ticketId)
        .eq('status', 'pending');
    return (listingsResponse as List).cast<Map<String, dynamic>>().firstOrNull;
  }

  Future<String> createResaleListing({
    required String ticketId,
    required String recipientUsername,
    required double askingPrice,
  }) async {
    final result = await _client.rpc(
      'create_ticket_listing',
      params: {
        'p_ticket_id': ticketId,
        'p_recipient_username': recipientUsername,
        'p_asking_price': askingPrice,
      },
    );
    return result as String;
  }

  Future<void> cancelResaleListing(String listingId) async {
    await _client.rpc(
      'cancel_ticket_listing',
      params: {'p_listing_id': listingId},
    );
  }
}
