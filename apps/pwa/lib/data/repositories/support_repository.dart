import 'package:supabase_flutter/supabase_flutter.dart';

class SupportRepository {
  final SupabaseClient _client;

  SupportRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// Fetches the FAQ CMS page for a given context
  Future<Map<String, dynamic>?> getFaqsByContext(String contextCategory) async {
    try {
      final slug = 'faq-$contextCategory';
      final response = await _client
          .schema('api')
          .from('v1_cms_pages')
          .select('content')
          .eq('slug', slug)
          .maybeSingle();

      if (response != null && response['content'] != null) {
        return response['content'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      // Return null or handle the error depending on the app's error handling strategy
      return null;
    }
  }

  /// Fetches active support tickets for the current user in a specific context
  Future<List<Map<String, dynamic>>> getActiveTickets(String userId, String contextCategory) async {
    try {
      final response = await _client
          .schema('api')
          .from('v1_support_tickets')
          .select('id, reference, subject, status, priority, created_at, updated_at, metadata')
          .eq('user_id', userId)
          .eq('metadata->>context', contextCategory)
          .inFilter('status', ['new', 'open', 'waiting_on_user']);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Streams real-time messages for a specific support ticket
  Stream<List<Map<String, dynamic>>> streamMessages(String ticketId) {
    return _client
        .schema('reports')
        .from('support_ticket_messages')
        .stream(primaryKey: ['id'])
        .eq('ticket_id', ticketId)
        .order('created_at');
  }

  /// Sends a new message to a support ticket
  Future<void> sendMessage(String ticketId, String userId, String message) async {
    final createdAt = DateTime.now().toIso8601String();
    await _client.schema('api').from('v1_support_ticket_messages').insert({
      'ticket_id': ticketId,
      'sender_id': userId,
      'message': message,
      'is_read': false,
      'created_at': createdAt,
    });
  }

  /// Creates a new support ticket
  Future<String> createTicket(String userId, String contextCategory, String subject, String message) async {
    final response = await _client.schema('api').from('v1_support_tickets').insert({
      'user_id': userId,
      'email': _client.auth.currentUser?.email ?? 'user@lynk-x.com',
      'subject': subject,
      'message': message,
      'metadata': {'context': contextCategory},
    }).select('id').single();

    return response['id'] as String;
  }

  /// Closes an active support ticket
  Future<void> closeTicket(String ticketId) async {
    await _client.schema('api').rpc('close_support_ticket', params: {'p_ticket_id': ticketId});
  }
}
