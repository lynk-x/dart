part of 'ticket_cubit.dart';

enum PurchaseStatus { idle, submitting, success, failure }

class TicketState {
  final bool isLoading;
  final TicketModel? ticket;
  final String? error;
  // Non-null when the ticket owner has a pending resale offer open.
  final Map<String, dynamic>? pendingListing;
  // Tracks the in-flight and completed purchase lifecycle.
  final PurchaseStatus purchaseStatus;
  final String? purchaseError;

  const TicketState({
    this.isLoading = false,
    this.ticket,
    this.error,
    this.pendingListing,
    this.purchaseStatus = PurchaseStatus.idle,
    this.purchaseError,
  });

  TicketState copyWith({
    bool? isLoading,
    TicketModel? ticket,
    String? error,
    Map<String, dynamic>? pendingListing,
    bool clearPendingListing = false,
    PurchaseStatus? purchaseStatus,
    String? purchaseError,
    bool clearPurchaseError = false,
  }) {
    return TicketState(
      isLoading: isLoading ?? this.isLoading,
      ticket: ticket ?? this.ticket,
      error: error ?? this.error,
      pendingListing: clearPendingListing ? null : (pendingListing ?? this.pendingListing),
      purchaseStatus: purchaseStatus ?? this.purchaseStatus,
      purchaseError: clearPurchaseError ? null : (purchaseError ?? this.purchaseError),
    );
  }
}
