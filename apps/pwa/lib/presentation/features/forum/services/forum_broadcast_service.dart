import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Listener callback invoked with the decoded Broadcast event payload.
typedef ForumBroadcastListener = void Function(Map<String, dynamic> payload);

/// Shared private Realtime Broadcast hub for a forum (`forum:<forumId>`).
///
/// Consolidates message changes (`forum_message_change`), forum status
/// transitions (`forum_status_change`), member role/mute changes
/// (`forum_member_change`), gallery media updates (`forum_media_change`),
/// and agenda session updates (`forum_session_change` / `session_mutation`)
/// onto **one ref-counted WebSocket channel per `forumId`**, replacing the
/// separate per-table `postgres_changes` subscriptions.
///
/// Message events arrive in bursts, so `forum_message_change` dispatch is
/// debounced (50ms) before notifying listeners; status/member/media/session
/// events dispatch immediately.
class ForumBroadcastService {
  static final ForumBroadcastService _instance =
      ForumBroadcastService._internal();
  factory ForumBroadcastService() => _instance;
  ForumBroadcastService._internal();

  static const List<String> _events = [
    'forum_message_change',
    'forum_status_change',
    'forum_member_change',
    'forum_media_change',
    'forum_session_change',
    'session_mutation',
  ];

  // One private Broadcast channel per forumId.
  final Map<String, RealtimeChannel> _channels = {};

  // Event-keyed listener lists per forumId: forumId -> eventName -> listeners.
  final Map<String, Map<String, List<ForumBroadcastListener>>> _listeners = {};

  // Total ref-count per forumId across all events — channel closes when 0.
  final Map<String, int> _refCounts = {};

  // Pending message payloads per forumId, drained on a 50ms timer.
  final Map<String, List<Map<String, dynamic>>> _pendingMessages = {};
  Timer? _debounceTimer;

  /// Registers [listener] to receive [event] payloads on `forum:$forumId`.
  ///
  /// Creates and subscribes the shared private Broadcast channel for [forumId]
  /// if one does not already exist.
  void register(
    String forumId,
    ForumBroadcastListener listener, {
    String event = 'forum_message_change',
  }) {
    final eventMap = _listeners.putIfAbsent(forumId, () => {});
    final list = eventMap.putIfAbsent(event, () => []);
    if (list.contains(listener)) return;
    list.add(listener);
    _refCounts[forumId] = (_refCounts[forumId] ?? 0) + 1;

    if (!_channels.containsKey(forumId)) {
      _createChannel(forumId);
    }
  }

  /// Unregisters [listener] for [event] on `forum:$forumId`.
  ///
  /// Unsubscribes and removes the shared Realtime channel once the last
  /// listener across all event types unregisters.
  void unregister(
    String forumId,
    ForumBroadcastListener listener, {
    String event = 'forum_message_change',
  }) {
    final removed = _listeners[forumId]?[event]?.remove(listener) ?? false;
    if (!removed) return;

    final remaining = ((_refCounts[forumId] ?? 1) - 1).clamp(0, 999);
    _refCounts[forumId] = remaining;

    if (remaining == 0) {
      _channels[forumId]?.unsubscribe();
      _channels.remove(forumId);
      _listeners.remove(forumId);
      _refCounts.remove(forumId);
      _pendingMessages.remove(forumId);
    }
  }

  /// Sends a client broadcast [event] with [payload] over `forum:$forumId` if active.
  void sendBroadcast(
    String forumId, {
    required String event,
    required Map<String, dynamic> payload,
  }) {
    _channels[forumId]?.sendBroadcastMessage(event: event, payload: payload);
  }

  void _createChannel(String forumId) {
    var channel = Supabase.instance.client.channel(
      'forum:$forumId',
      opts: const RealtimeChannelConfig(private: true),
    );

    for (final eventName in _events) {
      channel = channel.onBroadcast(
        event: eventName,
        callback: (payload) {
          if (eventName == 'forum_message_change') {
            _pendingMessages[forumId] ??= [];
            _pendingMessages[forumId]!.add(payload);
            _armDebounce();
          } else {
            _dispatchImmediate(forumId, eventName, payload);
          }
        },
      );
    }

    channel.subscribe();
    _channels[forumId] = channel;
  }

  void _dispatchImmediate(
    String forumId,
    String eventName,
    Map<String, dynamic> payload,
  ) {
    final listeners = List<ForumBroadcastListener>.from(
      _listeners[forumId]?[eventName] ?? const [],
    );
    for (final fn in listeners) {
      try {
        fn(payload);
      } catch (e, stack) {
        debugPrint(
          '[ForumBroadcastService] $eventName listener error for forum $forumId: $e\n$stack',
        );
      }
    }
  }

  /// Arms a 50ms debounce timer that drains [_pendingMessages] into one batch.
  void _armDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      _debounceTimer = null;
      for (final entry in _pendingMessages.entries) {
        final forumId = entry.key;
        final events = List<Map<String, dynamic>>.from(entry.value);
        entry.value.clear();
        if (events.isEmpty) continue;

        final listeners = List<ForumBroadcastListener>.from(
          _listeners[forumId]?['forum_message_change'] ?? const [],
        );
        for (final fn in listeners) {
          for (final payload in events) {
            try {
              fn(payload);
            } catch (e, stack) {
              debugPrint(
                '[ForumBroadcastService] forum_message_change listener error for forum $forumId: $e\n$stack',
              );
            }
          }
        }
      }
    });
  }
}
