part of 'ticket_cubit.dart';

class TicketState {
  final bool isLoading;
  final TicketModel? ticket;
  final String? error;
  // Non-null when the ticket owner has a pending resale offer open.
  final Map<String, dynamic>? pendingListing;

  const TicketState({
    this.isLoading = false,
    this.ticket,
    this.error,
    this.pendingListing,
  });

  TicketState copyWith({
    bool? isLoading,
    TicketModel? ticket,
    String? error,
    Map<String, dynamic>? pendingListing,
    bool clearPendingListing = false,
  }) {
    return TicketState(
      isLoading: isLoading ?? this.isLoading,
      ticket: ticket ?? this.ticket,
      error: error ?? this.error,
      pendingListing: clearPendingListing ? null : (pendingListing ?? this.pendingListing),
    );
  }
}
