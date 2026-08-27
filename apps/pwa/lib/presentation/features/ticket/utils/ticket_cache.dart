import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';

/// Local SharedPreferences cache for user tickets, used to provide instant 
/// offline access to active event tickets and passes at venue entrances.
class TicketCache {
  const TicketCache();

  static const String _kTicketsCacheKey = 'cached_user_tickets';

  /// Loads cached ticket list from local storage.
  Future<List<TicketModel>?> loadTickets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kTicketsCacheKey);
      if (jsonStr == null || jsonStr.isEmpty) return null;

      final decoded = jsonDecode(jsonStr) as List;
      return decoded
          .map((e) => TicketModel.fromView(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e, stack) {
      debugPrint('[TicketCache] loadTickets error: $e\n$stack');
      return null;
    }
  }

  /// Loads a single cached ticket by its reference string.
  Future<TicketModel?> loadTicketByReference(String reference) async {
    try {
      final tickets = await loadTickets();
      if (tickets == null) return null;
      for (final t in tickets) {
        if (t.reference == reference) return t;
      }
      return null;
    } catch (e, stack) {
      debugPrint('[TicketCache] loadTicketByReference error: $e\n$stack');
      return null;
    }
  }

  /// Persists ticket list to local storage.
  Future<void> saveTickets(List<TicketModel> tickets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encodedList = tickets.map((t) => t.toMap()).toList();
      await prefs.setString(_kTicketsCacheKey, jsonEncode(encodedList));
    } catch (e, stack) {
      debugPrint('[TicketCache] saveTickets error: $e\n$stack');
    }
  }

  /// Clears cached tickets (e.g. on logout).
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kTicketsCacheKey);
    } catch (e, stack) {
      debugPrint('[TicketCache] clearCache error: $e\n$stack');
    }
  }
}
