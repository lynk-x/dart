part of 'ticket_cubit.dart';

class TicketState {
  final bool isLoading;
  final TicketModel? ticket;
  final String? error;

  const TicketState({
    this.isLoading = false,
    this.ticket,
    this.error,
  });

  TicketState copyWith({
    bool? isLoading,
    TicketModel? ticket,
    String? error,
  }) {
    return TicketState(
      isLoading: isLoading ?? this.isLoading,
      ticket: ticket ?? this.ticket,
      error: error ?? this.error,
    );
  }
}
