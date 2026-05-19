import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/data/repositories/repositories.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';

part 'ticket_state.dart';

class TicketCubit extends Cubit<TicketState> {
  final TicketRepository _repo;
  TicketCubit(this._repo) : super(const TicketState());

  RealtimeChannel? _ticketChannel;
  RealtimeChannel? _listingChannel;

  Timer? _reconnectTimer;
  Duration _reconnectDelay = const Duration(seconds: 2);

  @override
  Future<void> close() {
    _ticketChannel?.unsubscribe();
    _listingChannel?.unsubscribe();
    _reconnectTimer?.cancel();
    return super.close();
  }

  Future<void> loadTicket(String ticketId, {bool isSilent = false}) async {
    if (!isSilent) emit(state.copyWith(isLoading: true, error: null));

    try {
      // 1. Fetch ticket data from the secure API proxy view via repository
      final response = await _repo.getTicketById(ticketId);
      if (response == null) {
        throw Exception('Ticket not found');
      }

      final ticket = TicketModel.fromView(response);

      // 2. Fetch pending listings separately via repository
      final pendingListing = await _repo.getPendingListing(ticketId);

      emit(state.copyWith(
        isLoading: false,
        ticket: ticket,
        pendingListing: pendingListing,
        clearPendingListing: pendingListing == null,
      ));

      // Subscribe to updates if not already listening for this ticket
      if (_ticketChannel == null) {
        _subscribeToUpdates(ticketId);
      }
    } catch (e) {
      if (!isSilent) emit(state.copyWith(isLoading: false, error: e.toFriendlyMessage()));
    }
  }

  void _subscribeToUpdates(String ticketId) {
    _ticketChannel?.unsubscribe();
    // Subscribe to ticket status updates through repository
    _ticketChannel = _repo.subscribeToTicket(ticketId, (payload) {
      // When the steward scans the QR code, redeemed_at is updated.
      // Re-fetch via the view to get the fresh status and nested event data.
      loadTicket(ticketId, isSilent: true);
    });

    _ticketChannel!.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        _scheduleTicketReconnect(ticketId);
      } else if (status == RealtimeSubscribeStatus.subscribed) {
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _reconnectDelay = const Duration(seconds: 2);
      }
    });

    // Subscribe to ticket_listings updates through repository so resale offer
    // status updates reflect immediately without requiring a manual refresh.
    _listingChannel?.unsubscribe();
    _listingChannel = _repo.subscribeToTicketListing(ticketId, (payload) {
      loadTicket(ticketId, isSilent: true);
    });
    _listingChannel!.subscribe();
  }

  void _scheduleTicketReconnect(String ticketId) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnectDelay = _reconnectDelay * 2;
      if (_reconnectDelay > const Duration(seconds: 30)) {
        _reconnectDelay = const Duration(seconds: 30);
      }
      _subscribeToUpdates(ticketId);
    });
  }

  Future<void> refresh() async {
    if (state.ticket != null) {
      await loadTicket(state.ticket!.id);
    }
  }

  /// Purchase tickets via the purchase_tickets RPC and track the full
  /// lifecycle through [PurchaseStatus] so screens can show a confirmation.
  Future<void> purchaseTickets({
    required String eventId,
    required String tierId,
    required int quantity,
    required String reservationId,
    String provider = 'in-app',
    String? promoCode,
  }) async {
    emit(state.copyWith(
      purchaseStatus: PurchaseStatus.submitting,
      clearPurchaseError: true,
    ));
    try {
      await _repo.purchaseTickets(
        eventId: eventId,
        tierId: tierId,
        quantity: quantity,
        reservationId: reservationId,
        provider: provider,
        promoCode: promoCode,
      );
      emit(state.copyWith(purchaseStatus: PurchaseStatus.success));
      // Refresh ticket list so the newly purchased ticket appears immediately.
      if (state.ticket != null) {
        await loadTicket(state.ticket!.id, isSilent: true);
      }
    } catch (e) {
      emit(state.copyWith(
        purchaseStatus: PurchaseStatus.failure,
        purchaseError: e.toFriendlyMessage(),
      ));
    }
  }

  /// Reset purchase state — call when the checkout sheet is dismissed.
  void resetPurchase() {
    emit(state.copyWith(
      purchaseStatus: PurchaseStatus.idle,
      clearPurchaseError: true,
    ));
  }

  Future<String> createResaleListing({
    required String recipientUsername,
    required double askingPrice,
  }) async {
    final ticketId = state.ticket?.id;
    if (ticketId == null) throw Exception('No ticket loaded');

    final result = await _repo.createResaleListing(
      ticketId: ticketId,
      recipientUsername: recipientUsername,
      askingPrice: askingPrice,
    );
    await loadTicket(ticketId, isSilent: true);
    return result;
  }

  Future<void> cancelResaleListing(String listingId) async {
    await _repo.cancelResaleListing(listingId);
    if (state.ticket != null) {
      await loadTicket(state.ticket!.id, isSilent: true);
    }
  }
}
