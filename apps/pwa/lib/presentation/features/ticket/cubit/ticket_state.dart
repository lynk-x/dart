part of 'ticket_cubit.dart';

enum PurchaseStatus { idle, submitting, success, failure }

enum RefundRequestStatus { idle, submitting, success, failure }

class TicketState {
  final bool isLoading;
  final TicketModel? ticket;
  final String? error;
  // Non-null when the ticket owner has a pending resale offer open.
  final Map<String, dynamic>? pendingListing;
  // Non-null when the ticket owner has a pending refund request open.
  final Map<String, dynamic>? pendingRefundRequest;
  // Tracks the in-flight and completed purchase lifecycle.
  final PurchaseStatus purchaseStatus;
  final String? purchaseError;
  // Tracks the in-flight and completed refund-request submission.
  final RefundRequestStatus refundRequestStatus;
  final String? refundRequestError;

  const TicketState({
    this.isLoading = false,
    this.ticket,
    this.error,
    this.pendingListing,
    this.pendingRefundRequest,
    this.purchaseStatus = PurchaseStatus.idle,
    this.purchaseError,
    this.refundRequestStatus = RefundRequestStatus.idle,
    this.refundRequestError,
  });

  TicketState copyWith({
    bool? isLoading,
    TicketModel? ticket,
    String? error,
    Map<String, dynamic>? pendingListing,
    bool clearPendingListing = false,
    Map<String, dynamic>? pendingRefundRequest,
    bool clearPendingRefundRequest = false,
    PurchaseStatus? purchaseStatus,
    String? purchaseError,
    bool clearPurchaseError = false,
    RefundRequestStatus? refundRequestStatus,
    String? refundRequestError,
    bool clearRefundRequestError = false,
  }) {
    return TicketState(
      isLoading: isLoading ?? this.isLoading,
      ticket: ticket ?? this.ticket,
      error: error ?? this.error,
      pendingListing: clearPendingListing ? null : (pendingListing ?? this.pendingListing),
      pendingRefundRequest: clearPendingRefundRequest ? null : (pendingRefundRequest ?? this.pendingRefundRequest),
      purchaseStatus: purchaseStatus ?? this.purchaseStatus,
      purchaseError: clearPurchaseError ? null : (purchaseError ?? this.purchaseError),
      refundRequestStatus: refundRequestStatus ?? this.refundRequestStatus,
      refundRequestError: clearRefundRequestError ? null : (refundRequestError ?? this.refundRequestError),
    );
  }
}
