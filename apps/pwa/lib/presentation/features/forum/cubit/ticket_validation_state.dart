import 'package:equatable/equatable.dart';

enum ScanStatus {
  idle,
  scanning,
  processing,
  success,
  alreadyScanned,
  error,
}

class ScanHistoryItem extends Equatable {
  final String code;
  final String? attendeeName;
  final String? username;
  final ScanStatus status;
  final String? errorMessage;
  final DateTime timestamp;

  const ScanHistoryItem({
    required this.code,
    this.attendeeName,
    this.username,
    required this.status,
    this.errorMessage,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'attendeeName': attendeeName,
      'username': username,
      'status': status.name,
      'errorMessage': errorMessage,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ScanHistoryItem.fromJson(Map<String, dynamic> json) {
    return ScanHistoryItem(
      code: json['code'] as String,
      attendeeName: json['attendeeName'] as String?,
      username: json['username'] as String?,
      status: ScanStatus.values.byName(json['status'] as String),
      errorMessage: json['errorMessage'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  @override
  List<Object?> get props => [code, attendeeName, username, status, errorMessage, timestamp];
}

class TicketValidationState extends Equatable {
  final List<Map<String, dynamic>> tickets;
  final bool isLoading;
  final String? error;
  final DateTime? lastSyncedAt;
  final List<ScanHistoryItem> scanHistory;

  const TicketValidationState({
    this.tickets = const [],
    this.isLoading = false,
    this.error,
    this.lastSyncedAt,
    this.scanHistory = const [],
  });

  TicketValidationState copyWith({
    List<Map<String, dynamic>>? tickets,
    bool? isLoading,
    String? error,
    bool clearError = false,
    DateTime? lastSyncedAt,
    List<ScanHistoryItem>? scanHistory,
  }) {
    return TicketValidationState(
      tickets: tickets ?? this.tickets,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      scanHistory: scanHistory ?? this.scanHistory,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tickets': tickets,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'scanHistory': scanHistory.map((item) => item.toJson()).toList(),
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
      scanHistory: List<ScanHistoryItem>.from(
        (json['scanHistory'] as List?)?.map((e) => ScanHistoryItem.fromJson(Map<String, dynamic>.from(e as Map))) ?? [],
      ),
    );
  }

  @override
  List<Object?> get props => [tickets, isLoading, error, lastSyncedAt, scanHistory];
}
