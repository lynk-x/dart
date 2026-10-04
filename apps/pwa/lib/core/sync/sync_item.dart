import 'dart:convert';

/// Types of database mutations supported by the offline sync queue.
enum SyncAction { insert, update, delete, rpc }

/// Determines how [SyncManager] handles concurrent edits when the remote row is newer
/// than the client's baseline timestamp.
///
/// - [ConflictPolicy.serverWins]: Skips local write and emits `false` on `statusStream`.
///   Dispatches a [SyncConflict] event on `conflictStream` for optional UI rollback handling.
/// - [ConflictPolicy.clientWins]: Writes unconditionally without pre-checking baseline timestamp.
/// - [ConflictPolicy.manual]: Holds the item in the sync queue and dispatches a [SyncConflict].
///   The item remains paused until [SyncManager.resolveConflict] is called.
enum ConflictPolicy {
  serverWins,
  clientWins,
  manual,
}

/// Represents a queued offline mutation pending synchronization with Supabase.
class SyncItem {
  final String id;
  final String table;
  final String? schema;
  final SyncAction action;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  int retryCount;

  /// How to handle a write conflict on UPDATE.
  /// Ignored for INSERT and DELETE actions.
  final ConflictPolicy conflictPolicy;

  /// The `updated_at` ISO 8601 string the client last observed for this row.
  /// Set this when constructing an UPDATE SyncItem so the manager can detect
  /// whether the server has advanced since the client read the row.
  ///
  /// If null, no conflict detection is performed (equivalent to [ConflictPolicy.clientWins]).
  final String? serverUpdatedAtBaseline;

  /// Partition key column name for partitioned tables (e.g. `'created_at'`,
  /// `'transferred_at'`, `'scanned_at'`). When set, UPDATE/DELETE operations
  /// also filter by this column to satisfy the composite primary key required
  /// by Postgres partitioned tables.
  ///
  /// Required for: `forum_messages.forum_messages`, `forum_media.forum_media`,
  /// `message_reactions.message_reactions`, `notifications.notifications`,
  /// `tickets.tickets`, `ticket_transfers.ticket_transfers`,
  /// `refund_requests.refund_requests`, `transactions.transactions`,
  /// `wallet_top_ups.wallet_top_ups`, `responses.responses`, `reports.reports`,
  /// `ad_analytics.ad_analytics`, `ticket_scan_logs.ticket_scan_logs`.
  final String? partitionKeyName;

  /// Partition key value (typically an ISO 8601 timestamp). Must be the exact
  /// value that was used at INSERT time — read it back from the row, do not
  /// regenerate `DateTime.now()` here.
  final String? partitionKeyValue;

  SyncItem({
    required this.id,
    required this.table,
    this.schema,
    required this.action,
    required this.payload,
    DateTime? createdAt,
    this.retryCount = 0,
    this.conflictPolicy = ConflictPolicy.serverWins,
    this.serverUpdatedAtBaseline,
    this.partitionKeyName,
    this.partitionKeyValue,
  }) : createdAt = createdAt ?? DateTime.now();

  SyncItem copyWith({int? retryCount}) => SyncItem(
        id: id,
        table: table,
        schema: schema,
        action: action,
        payload: payload,
        createdAt: createdAt,
        retryCount: retryCount ?? this.retryCount,
        conflictPolicy: conflictPolicy,
        serverUpdatedAtBaseline: serverUpdatedAtBaseline,
        partitionKeyName: partitionKeyName,
        partitionKeyValue: partitionKeyValue,
      );

  /// Serializes this sync item to a JSON-compatible map for persistent storage.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'table': table,
      'schema': schema,
      'action': action.name,
      'payload': jsonEncode(payload),
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
      'conflictPolicy': conflictPolicy.name,
      'serverUpdatedAtBaseline': serverUpdatedAtBaseline,
      'partitionKeyName': partitionKeyName,
      'partitionKeyValue': partitionKeyValue,
    };
  }

  /// Deserializes a persisted sync item from a storage map.
  factory SyncItem.fromMap(Map<String, dynamic> map) {
    return SyncItem(
      id: map['id'] as String,
      table: map['table'] as String,
      schema: map['schema'] as String?,
      action: SyncAction.values.byName(map['action'] as String),
      payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
      createdAt: DateTime.parse(map['createdAt'] as String),
      retryCount: map['retryCount'] as int,
      conflictPolicy: ConflictPolicy.values.byName(
        (map['conflictPolicy'] as String?) ?? ConflictPolicy.serverWins.name,
      ),
      serverUpdatedAtBaseline: map['serverUpdatedAtBaseline'] as String?,
      partitionKeyName: map['partitionKeyName'] as String?,
      partitionKeyValue: map['partitionKeyValue'] as String?,
    );
  }
}

/// Represents an unresolved write conflict emitted when remote data is newer than local baseline.
class SyncConflict {
  /// Unique identifier of the [SyncItem] triggering the conflict.
  final String itemId;

  /// Database table where the collision occurred.
  final String table;

  /// Local payload that was scheduled to be written.
  final Map<String, dynamic> clientVersion;

  /// Current remote row snapshot retrieved from the server.
  final Map<String, dynamic> serverVersion;

  /// The policy applied during detection.
  final ConflictPolicy policy;

  const SyncConflict({
    required this.itemId,
    required this.table,
    required this.clientVersion,
    required this.serverVersion,
    required this.policy,
  });
}

/// User or programmatic resolution for a conflict held under [ConflictPolicy.manual].
enum ConflictResolution {
  /// Overwrite remote state with the queued local payload.
  applyClient,

  /// Discard the queued local write and retain remote server state.
  discardClient,
}
