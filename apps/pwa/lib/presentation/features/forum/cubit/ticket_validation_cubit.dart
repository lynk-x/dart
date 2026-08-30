import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/core/sync/sync_item.dart';
import 'package:lynk_x/core/sync/sync_manager.dart';
import 'ticket_validation_state.dart';

class TicketValidationCubit extends HydratedCubit<TicketValidationState> {
  final String eventId;
  final DateTime eventCreatedAt;

  TicketValidationCubit({
    required this.eventId,
    required this.eventCreatedAt,
  }) : super(const TicketValidationState());

  @override
  String get id => eventId;

  /// Fetches the latest ticket registry from the server and caches it locally.
  Future<void> fetchTickets() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final response = await Supabase.instance.client
          .schema('api')
          .from('v1_tickets')
          .select()
          .eq('event_id', eventId);

      final List<Map<String, dynamic>> tickets = List<Map<String, dynamic>>.from(response);

      if (!isClosed) {
        emit(state.copyWith(
          tickets: tickets,
          isLoading: false,
          lastSyncedAt: DateTime.now(),
        ));
      }
    } catch (e, stack) {
      debugPrint('[TicketValidationCubit] Error fetching tickets: $e\n$stack');
      if (!isClosed) {
        emit(state.copyWith(
          isLoading: false,
          error: e.toString(),
        ));
      }
    }
  }

  /// Checks whether input match a ticket record by code, reference, or formatted reference.
  bool _matchesTicket(Map<String, dynamic> t, String rawSanitizedInput) {
    final sanitizedInput = rawSanitizedInput.split('|').first.trim();
    final code = t['ticket_code']?.toString().trim().replaceAll(RegExp(r'^#|^"|"$|[\r\n]'), '').toLowerCase() ?? '';
    final ref = t['reference']?.toString().trim().replaceAll(RegExp(r'^#|^"|"$|[\r\n]'), '').toLowerCase() ?? '';
    final cleanRef = TicketModel.formatCleanReference(t['reference']?.toString() ?? t['ticket_code']?.toString()).toLowerCase();

    final codeNoHyphen = code.replaceAll('-', '');
    final refNoHyphen = ref.replaceAll('-', '');
    final cleanRefNoHyphen = cleanRef.replaceAll('-', '');
    final inputNoHyphen = sanitizedInput.replaceAll('-', '');

    if (inputNoHyphen.isEmpty) return false;

    return code == sanitizedInput ||
        ref == sanitizedInput ||
        cleanRef == sanitizedInput ||
        codeNoHyphen == inputNoHyphen ||
        refNoHyphen == inputNoHyphen ||
        cleanRefNoHyphen == inputNoHyphen ||
        (codeNoHyphen.isNotEmpty && codeNoHyphen.startsWith(inputNoHyphen)) ||
        (refNoHyphen.isNotEmpty && refNoHyphen.startsWith(inputNoHyphen)) ||
        (cleanRefNoHyphen.isNotEmpty && cleanRefNoHyphen.startsWith(inputNoHyphen)) ||
        (inputNoHyphen.isNotEmpty && inputNoHyphen.startsWith(codeNoHyphen)) ||
        (inputNoHyphen.isNotEmpty && inputNoHyphen.startsWith(refNoHyphen)) ||
        (inputNoHyphen.isNotEmpty && inputNoHyphen.startsWith(cleanRefNoHyphen));
  }

  /// Performs a read-only dry-run lookup of a ticket by reference or code without modifying its status.
  Map<String, dynamic>? lookupTicketOffline(String inputCode) {
    final tickets = List<Map<String, dynamic>>.from(state.tickets);
    final primaryInput = inputCode.trim().split('|').first.trim();
    final sanitizedCode = primaryInput.replaceAll(RegExp(r'^#|^"|"$|[\r\n]'), '').toLowerCase();

    final ticketIndex = tickets.indexWhere((t) => _matchesTicket(t, sanitizedCode));

    if (ticketIndex == -1) return null;
    return tickets[ticketIndex];
  }

  /// Performs local offline-first ticket validation.
  /// Marks the ticket as used locally and queues a background sync job.
  Future<Map<String, dynamic>> scanTicketOffline(
    String ticketCode, {
    String? scannerUserId,
  }) async {
    final tickets = List<Map<String, dynamic>>.from(state.tickets);
    final primaryCode = ticketCode.trim().split('|').first.trim();
    final sanitizedCode = primaryCode.replaceAll(RegExp(r'^#|^"|"$|[\r\n]'), '').toLowerCase();

    final ticketIndex = tickets.indexWhere((t) => _matchesTicket(t, sanitizedCode));

    if (ticketIndex == -1) {
      return {
        'success': false,
        'error': 'Invalid Ticket Code',
      };
    }

    final ticket = tickets[ticketIndex];
    final String status = ticket['status']?.toString() ?? 'valid';

    if (status == 'used') {
      return {
        'success': false,
        'error': 'Ticket already checked in',
        'attendee_name': ticket['holder_name'],
        'redeemed_at': ticket['redeemed_at'],
      };
    }

    if (status != 'valid') {
      return {
        'success': false,
        'error': 'Ticket is $status',
      };
    }

    // Update ticket state locally (optimistic local check-in)
    final updatedTicket = Map<String, dynamic>.from(ticket);
    final String redeemedAtStr = DateTime.now().toUtc().toIso8601String();
    updatedTicket['status'] = 'used';
    updatedTicket['redeemed_at'] = redeemedAtStr;
    tickets[ticketIndex] = updatedTicket;

    emit(state.copyWith(tickets: tickets));

    // Queue the scan for sync when network is restored. api.scan_ticket
    // treats p_scanner_user_id as optional (COALESCEs to auth.uid() server-side
    // if absent) — omit the key entirely rather than send '', which Postgres
    // would reject as an invalid uuid literal and get stuck retrying forever.
    final String? actualScannerId = scannerUserId ?? Supabase.instance.client.auth.currentUser?.id;
    final syncItem = SyncItem(
      id: 'scan_${eventId}_${ticketCode}_${DateTime.now().millisecondsSinceEpoch}',
      table: 'scan_ticket',
      schema: 'api',
      action: SyncAction.rpc,
      payload: {
        'p_event_id': eventId,
        'p_event_created_at': eventCreatedAt.toIso8601String(),
        'p_ticket_code': primaryCode,
        if (actualScannerId != null) 'p_scanner_user_id': actualScannerId,
      },
    );

    SyncManager.instance.addWork(syncItem);

    return {
      'success': true,
      'attendee_name': ticket['holder_name'],
      'username': ticket['holder_email']?.toString().split('@').first, // Fallback since v1_tickets lacks username
      'tier_name': ticket['tier_name'] ?? '',
    };
  }

  void clearError() {
    emit(state.copyWith(clearError: true));
  }

  void addScanHistoryItem(ScanHistoryItem item) {
    final updatedHistory = List<ScanHistoryItem>.from(state.scanHistory)..insert(0, item);
    emit(state.copyWith(scanHistory: updatedHistory));
  }

  void clearScanHistory() {
    emit(state.copyWith(scanHistory: const []));
  }

  @override
  TicketValidationState? fromJson(Map<String, dynamic> json) => TicketValidationState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(TicketValidationState state) => state.toJson();
}
