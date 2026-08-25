import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared Postgres CDC (Change Data Capture) service for the forum messages table.
///
/// ## Problem solved
/// `BaseMessageCubit` previously created **one dedicated Realtime channel per cubit
/// per forum** (e.g. `forum_messages_cdc_chat_$forumId` and
/// `forum_messages_cdc_announcement_$forumId`). Both subscribed to the **same**
/// `social.forum_messages` table with the same `forum_id` filter, opening two
/// identical WebSocket subscriptions for one forum page load.
///
/// ## Solution
/// This singleton maintains **one channel per `forumId`** regardless of how many
/// cubits are active. Each cubit [register]s a typed listener; incoming CDC events
/// are dispatched to every registered listener and each listener is responsible for
/// filtering by its own `messageTypes`.
///
/// ## Lifecycle
/// - The channel is created on the **first** [register] call for a given `forumId`.
/// - Internally ref-counted: the channel is unsubscribed and removed when the last
///   listener [unregister]s.
class ForumCdcService {
  static final ForumCdcService _instance = ForumCdcService._internal();
  factory ForumCdcService() => _instance;
  ForumCdcService._internal();

  // One Realtime channel per forumId.
  final Map<String, RealtimeChannel> _channels = {};

  // Listener lists per forumId — snapshot before dispatch to avoid concurrent modification.
  final Map<String, List<void Function(PostgresChangePayload)>> _listeners = {};

  // Ref-counts per forumId — channel is torn down when this reaches zero.
  final Map<String, int> _refCounts = {};

  /// Registers [listener] to receive CDC events for [forumId].
  ///
  /// Creates the shared Realtime channel for [forumId] if one does not already
  /// exist. Safe to call multiple times for the same [forumId].
  void register(String forumId, void Function(PostgresChangePayload) listener) {
    _listeners.putIfAbsent(forumId, () => []).add(listener);
    _refCounts[forumId] = (_refCounts[forumId] ?? 0) + 1;

    if (!_channels.containsKey(forumId)) {
      _createChannel(forumId);
    }
  }

  /// Unregisters [listener] from CDC events for [forumId].
  ///
  /// When the last listener for a [forumId] is removed the underlying Realtime
  /// channel is automatically unsubscribed and cleaned up.
  void unregister(String forumId, void Function(PostgresChangePayload) listener) {
    _listeners[forumId]?.remove(listener);
    final remaining = ((_refCounts[forumId] ?? 1) - 1).clamp(0, 999);
    _refCounts[forumId] = remaining;

    if (remaining == 0) {
      _channels[forumId]?.unsubscribe();
      _channels.remove(forumId);
      _listeners.remove(forumId);
      _refCounts.remove(forumId);
    }
  }

  void _createChannel(String forumId) {
    final channel = Supabase.instance.client
        .channel('forum_messages_cdc_$forumId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'social',
          table: 'forum_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'forum_id',
            value: forumId,
          ),
          callback: (payload) {
            // Snapshot listener list to guard against concurrent modification
            // if a cubit disposes (and unregisters) during dispatch.
            final listeners = List<void Function(PostgresChangePayload)>.from(
              _listeners[forumId] ?? const [],
            );
            for (final fn in listeners) {
              try {
                fn(payload);
              } catch (e, stack) {
                debugPrint('[ForumCdcService] listener error for forum $forumId: $e\n$stack');
              }
            }
          },
        );

    channel.subscribe();
    _channels[forumId] = channel;
  }
}
