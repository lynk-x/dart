import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/data/repositories/repositories.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';

import 'package:lynk_x/presentation/features/ticket/utils/ticket_cache.dart';

part 'ticket_state.dart';

class TicketCubit extends Cubit<TicketState> {
  final TicketRepository _repo;
  final TicketCache _cache;
  TicketCubit(this._repo, [this._cache = const TicketCache()]) : super(const TicketState());

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

  /// [reference] is the human-readable public ticket reference (used for
  /// routing/URLs). Internally, once the ticket is loaded, realtime
  /// subscriptions and RPC calls key on the real ticket id instead.
  Future<void> loadTicket(String reference, {bool isSilent = false}) async {
    // Attempt instant load from offline cache
    final cached = await _cache.loadTicketByReference(reference);
    if (cached != null) {
      emit(state.copyWith(isLoading: false, ticket: cached));
    } else if (!isSilent) {
      emit(state.copyWith(isLoading: true, error: null));
    }

    try {

      // 1. Fetch ticket data from the secure API proxy view via repository
      final response = await _repo.getTicketByReference(reference);
      if (response == null) {
        if (state.ticket == null) {
          throw Exception('Ticket not found');
        }
        return;
      }

      final ticket = TicketModel.fromView(response);

      // 2. Fetch pending listings and pending refund request separately via repository
      final results = await Future.wait([
        _repo.getPendingListing(ticket.id),
        _repo.getPendingRefundRequest(ticket.id),
      ]);
      final pendingListing = results[0];
      final pendingRefundRequest = results[1];

      emit(state.copyWith(
        isLoading: false,
        ticket: ticket,
        pendingListing: pendingListing,
        clearPendingListing: pendingListing == null,
        pendingRefundRequest: pendingRefundRequest,
        clearPendingRefundRequest: pendingRefundRequest == null,
      ));

      // Subscribe to updates if not already listening for this ticket
      if (_ticketChannel == null) {
        _subscribeToUpdates(ticket.id, reference);
      }
    } catch (e) {
      if (state.ticket == null && !isSilent) {
        emit(state.copyWith(isLoading: false, error: e.toFriendlyMessage()));
      } else {
        emit(state.copyWith(isLoading: false));
      }
    }
  }

  void _subscribeToUpdates(String ticketId, String reference) {
    _ticketChannel?.unsubscribe();
    // Subscribe to ticket status updates through repository
    _ticketChannel = _repo.subscribeToTicket(ticketId, (payload) {
      // When the steward scans the QR code, redeemed_at is updated.
      // Re-fetch via the view to get the fresh status and nested event data.
      loadTicket(reference, isSilent: true);
    });

    _ticketChannel!.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        _scheduleTicketReconnect(ticketId, reference);
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
      loadTicket(reference, isSilent: true);
    });
    _listingChannel!.subscribe();
  }

  void _scheduleTicketReconnect(String ticketId, String reference) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnectDelay = _reconnectDelay * 2;
      if (_reconnectDelay > const Duration(seconds: 30)) {
        _reconnectDelay = const Duration(seconds: 30);
      }
      _subscribeToUpdates(ticketId, reference);
    });
  }

  Future<void> refresh() async {
    if (state.ticket != null) {
      await loadTicket(state.ticket!.reference);
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
        await loadTicket(state.ticket!.reference, isSilent: true);
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

  Future<void> transferTicket(String recipientUsername) async {
    final ticket = state.ticket;
    if (ticket == null) throw Exception('No ticket loaded');

    await _repo.transferTicket(ticket.id, recipientUsername);
    await loadTicket(ticket.reference, isSilent: true);
  }

  /// Live "does this user exist" check while typing a recipient username
  /// into a transfer/resale form.
  Future<bool> checkUsernameExists(String username) => _repo.checkUsernameExists(username);

  Future<String> createResaleListing({
    required String recipientUsername,
    required double askingPrice,
  }) async {
    final ticket = state.ticket;
    if (ticket == null) throw Exception('No ticket loaded');

    final result = await _repo.createResaleListing(
      ticketId: ticket.id,
      recipientUsername: recipientUsername,
      askingPrice: askingPrice,
    );
    await loadTicket(ticket.reference, isSilent: true);
    return result;
  }

  Future<void> cancelResaleListing(String listingId) async {
    await _repo.cancelResaleListing(listingId);
    if (state.ticket != null) {
      await loadTicket(state.ticket!.reference, isSilent: true);
    }
  }

  /// Submits a refund request for organizer review. Ticket stays valid
  /// until approved/rejected from the organizer dashboard.
  Future<void> requestRefund(String reason) async {
    final ticket = state.ticket;
    if (ticket == null) throw Exception('No ticket loaded');

    emit(state.copyWith(
      refundRequestStatus: RefundRequestStatus.submitting,
      clearRefundRequestError: true,
    ));
    try {
      final result = await _repo.requestRefund(ticketId: ticket.id, reason: reason);
      if (result['success'] != true) {
        throw Exception(result['error'] as String? ?? 'Failed to submit refund request');
      }
      emit(state.copyWith(refundRequestStatus: RefundRequestStatus.success));
      await loadTicket(ticket.reference, isSilent: true);
    } catch (e) {
      emit(state.copyWith(
        refundRequestStatus: RefundRequestStatus.failure,
        refundRequestError: e.toFriendlyMessage(),
      ));
    }
  }

  /// Reset refund-request state — call when the dialog closes.
  void resetRefundRequest() {
    emit(state.copyWith(
      refundRequestStatus: RefundRequestStatus.idle,
      clearRefundRequestError: true,
    ));
  }
}
