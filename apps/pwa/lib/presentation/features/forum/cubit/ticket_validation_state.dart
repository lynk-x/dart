import 'package:equatable/equatable.dart';

class TicketValidationState extends Equatable {
  final List<Map<String, dynamic>> tickets;
  final bool isLoading;
  final String? error;
  final DateTime? lastSyncedAt;

  const TicketValidationState({
    this.tickets = const [],
    this.isLoading = false,
    this.error,
    this.lastSyncedAt,
  });

  TicketValidationState copyWith({
    List<Map<String, dynamic>>? tickets,
    bool? isLoading,
    String? error,
    bool clearError = false,
    DateTime? lastSyncedAt,
  }) {
    return TicketValidationState(
      tickets: tickets ?? this.tickets,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tickets': tickets,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    };
  }

  factory TicketValidationState.fromJson(Map<String, dynamic> json) {
    return TicketValidationState(
      tickets: List<Map<String, dynamic>>.from(
        (json['tickets'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? [],
      ),
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.tryParse(json['lastSyncedAt'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [tickets, isLoading, error, lastSyncedAt];
}
