import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/notification_preference_model.dart';

class NotificationPreferencesRepository {
  final SupabaseClient _client;
  NotificationPreferencesRepository(this._client);

  /// The togglable category list (already excludes auth/account_security).
  Future<List<NotificationCategory>> getCategories() async {
    final data = await _client
        .schema('api')
        .from('v1_notification_types')
        .select('id, display_name, description, default_email');
    return (data as List)
        .map((row) => NotificationCategory.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Only returns rows the user has explicitly set; categories with no row
  /// yet fall back to [NotificationPreference]'s defaults client-side.
  Future<List<NotificationPreference>> getPreferences() async {
    final data = await _client
        .schema('api')
        .rpc('get_user_notification_preferences');
    return (data as List)
        .map((row) => NotificationPreference.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> upsertPreference({
    required String type,
    required bool inApp,
    required bool push,
    required bool email,
  }) async {
    await _client.schema('api').rpc('upsert_notification_preferences', params: {
      'p_type': type,
      'p_in_app': inApp,
      'p_push': push,
      'p_email': email,
    });
  }
}
