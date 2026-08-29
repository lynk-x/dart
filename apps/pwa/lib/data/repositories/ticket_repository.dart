import 'package:supabase_flutter/supabase_flutter.dart';

class TicketRepository {
  final SupabaseClient _client;
  TicketRepository(this._client);

  /// Keyset-paginated: pass the (created_at, ticket_id) of the last row from
  /// the previous page as [beforeCreatedAt]/[beforeTicketId] to fetch the
  /// next page. Omit both for the first page.
  Future<List<Map<String, dynamic>>> getUserTickets(
    String userId, {
    int limit = 20,
    String? beforeCreatedAt,
    String? beforeTicketId,
  }) async {
    var query = _client
        .schema('api')
        .from('v1_user_tickets')
        .select()
        .eq('user_id', userId);

    if (beforeCreatedAt != null && beforeTicketId != null) {
      // (created_at, ticket_id) < (cursor) — matches the DESC ordering below.
      query = query.or(
        'created_at.lt.$beforeCreatedAt,'
        'and(created_at.eq.$beforeCreatedAt,ticket_id.lt.$beforeTicketId)',
      );
    }

    final data = await query
        .order('created_at', ascending: false)
        .order('ticket_id', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>?> getTicketByReference(String reference) async {
    return await _client
        .schema('api')
        .from('v1_user_tickets')
        .select()
        .eq('reference', reference)
        .maybeSingle();
  }

  Future<Map<String, dynamic>?> getTicketByEventId(String eventId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    return await _client
        .schema('api')
        .from('v1_user_tickets')
        .select()
        .eq('user_id', userId)
        .eq('event_id', eventId)
        .maybeSingle();
  }

  Future<void> transferTicket(String ticketId, String recipientUsername) async {
    await _client.schema('api').rpc('transfer_ticket', params: {
      'p_ticket_id': ticketId,
      'p_recipient_username': recipientUsername,
    });
  }

  /// Used to give live "recipient found" feedback while typing a username
  /// into a transfer/resale form, before submitting the RPC.
  Future<bool> checkUsernameExists(String username) async {
    final data = await _client
        .schema('api')
        .from('v1_profiles')
        .select('user_name')
        .eq('user_name', username)
        .maybeSingle();
    return data != null;
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
    final result = await _client.schema('api').rpc('lock_tickets_for_checkout', params: {
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
    final result = await _client.schema('api').rpc('purchase_tickets', params: {
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
    final result = await _client.schema('api').rpc(
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
    await _client.schema('api').rpc(
      'cancel_ticket_listing',
      params: {'p_listing_id': listingId},
    );
  }

  /// Submits a refund request for organizer review. Tickets are
  /// non-refundable by default (all sales final — attendees who can't
  /// attend should use ticket resale instead); this is a discretionary
  /// request, not a guaranteed refund. The ticket stays valid until the
  /// organizer approves/rejects it from their dashboard.
  Future<Map<String, dynamic>> requestRefund({
    required String ticketId,
    required String reason,
  }) async {
    final result = await _client.schema('api').rpc(
      'request_ticket_refund',
      params: {'p_ticket_id': ticketId, 'p_reason': reason},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  /// The caller's own pending refund request for [ticketId], if any — used
  /// to show request status on the ticket screen instead of letting the
  /// attendee submit a duplicate.
  Future<Map<String, dynamic>?> getPendingRefundRequest(String ticketId) async {
    return await _client
        .schema('api')
        .from('v1_refund_requests')
        .select('id, status, amount, currency, reason, created_at')
        .eq('ticket_id', ticketId)
        .eq('status', 'pending')
        .maybeSingle();
  }
}
