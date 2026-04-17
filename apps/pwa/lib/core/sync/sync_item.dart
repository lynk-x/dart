import 'dart:convert';

enum SyncAction { insert, update, delete, rpc }

/// Determines how the SyncManager behaves when it detects that the server row
/// was modified after the client read it (i.e. `server.updated_at > baseline`).
///
/// - [serverWins]:  Skip the write. The local optimistic state is reverted via
///                  `statusStream { id: false }`. A [SyncConflict] is also emitted
///                  on `conflictStream` with the server's current row for display.
///
/// - [clientWins]:  Write unconditionally — no pre-check performed. Suitable for
///                  truly local preferences (notification settings, UI state) where
///                  the user's intent should always override whatever the server has.
///
/// - [manual]:      Pause the item in the queue and emit a [SyncConflict] with both
///                  versions. Nothing is written or reverted until the caller invokes
///                  `SyncManager.instance.resolveConflict(id, resolution)`.
enum ConflictPolicy {
  serverWins,
  clientWins,
  manual,
}

class SyncItem {
  final String id;
  final String table;
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

  SyncItem({
    required this.id,
    required this.table,
    required this.action,
    required this.payload,
    DateTime? createdAt,
    this.retryCount = 0,
    this.conflictPolicy = ConflictPolicy.serverWins,
    this.serverUpdatedAtBaseline,
  }) : createdAt = createdAt ?? DateTime.now();

  SyncItem copyWith({int? retryCount}) => SyncItem(
        id: id,
        table: table,
        action: action,
        payload: payload,
        createdAt: createdAt,
        retryCount: retryCount ?? this.retryCount,
        conflictPolicy: conflictPolicy,
        serverUpdatedAtBaseline: serverUpdatedAtBaseline,
      );

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'table': table,
      'action': action.name,
      'payload': jsonEncode(payload),
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
      'conflictPolicy': conflictPolicy.name,
      'serverUpdatedAtBaseline': serverUpdatedAtBaseline,
    };
  }

  factory SyncItem.fromMap(Map<String, dynamic> map) {
    return SyncItem(
      id: map['id'] as String,
      table: map['table'] as String,
      action: SyncAction.values.byName(map['action'] as String),
      payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
      createdAt: DateTime.parse(map['createdAt'] as String),
      retryCount: map['retryCount'] as int,
      conflictPolicy: ConflictPolicy.values.byName(
        (map['conflictPolicy'] as String?) ?? ConflictPolicy.serverWins.name,
      ),
      serverUpdatedAtBaseline: map['serverUpdatedAtBaseline'] as String?,
    );
  }
}

/// Emitted on [SyncManager.conflictStream] when a write conflict is detected.
class SyncConflict {
  /// ID of the [SyncItem] that triggered the conflict.
  final String itemId;

  /// The table where the conflict occurred.
  final String table;

  /// The client's intended write (from [SyncItem.payload]).
  final Map<String, dynamic> clientVersion;

  /// The current server row at the time the conflict was detected.
  final Map<String, dynamic> serverVersion;

  /// The conflict policy that was active when the conflict was detected.
  final ConflictPolicy policy;

  const SyncConflict({
    required this.itemId,
    required this.table,
    required this.clientVersion,
    required this.serverVersion,
    required this.policy,
  });
}

/// Resolution provided by the caller when a [ConflictPolicy.manual] conflict
/// is held in the queue.
enum ConflictResolution {
  /// Apply the client's version — write the queued payload.
  applyClient,

  /// Discard the queued write — keep the server's current version.
  discardClient,
}
