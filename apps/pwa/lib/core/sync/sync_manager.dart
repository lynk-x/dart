import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sync_item.dart';

/// SyncManager
///
/// Orchestrates background synchronisation for the PWA.
/// Enables "Optimistic UI" by queuing actions and retrying them when network
/// returns.
///
/// ## Conflict Detection (UPDATE actions only)
///
/// When a [SyncItem] has [SyncItem.serverUpdatedAtBaseline] set, the manager
/// fetches the current `updated_at` from the server before committing the write
/// and compares it to the baseline:
///
///   • [ConflictPolicy.serverWins] — if server is newer, skip the write, emit
///     `{id: false}` on [statusStream] (cubit reverts optimistic state), and
///     emit a [SyncConflict] on [conflictStream].
///
///   • [ConflictPolicy.clientWins] — skip the pre-check entirely and write
///     unconditionally. No conflict event is emitted.
///
///   • [ConflictPolicy.manual]     — pause the item in the queue without
///     advancing and emit a [SyncConflict]. Nothing is written until the caller
///     invokes [resolveConflict].
///
/// INSERT and DELETE actions never trigger conflict detection.
class SyncManager {
  SyncManager._();
  static final instance = SyncManager._();

  final List<SyncItem> _queue = [];

  /// Item IDs paused pending manual conflict resolution.
  final Set<String> _pausedIds = {};

  bool _isSyncing = false;

  /// `{itemId: success}` broadcast — consumed by cubits to confirm or revert
  /// their optimistic state.
  final _statusController = StreamController<Map<String, bool>>.broadcast();
  Stream<Map<String, bool>> get statusStream => _statusController.stream;

  /// Conflict events — consumed by UI layers that need to present a resolution
  /// dialog. Only emitted for [ConflictPolicy.serverWins] and
  /// [ConflictPolicy.manual].
  final _conflictController = StreamController<SyncConflict>.broadcast();
  Stream<SyncConflict> get conflictStream => _conflictController.stream;

  /// Add a pending action to the queue.
  /// The calling cubit should have already applied its optimistic state update.
  void addWork(SyncItem item) {
    debugPrint('[SyncManager] Queued ${item.action.name} on ${item.table} (id=${item.id})');
    _queue.add(item);
    _processQueue();
  }

  /// Resolve a [ConflictPolicy.manual] conflict that was previously paused.
  ///
  /// [resolution] == [ConflictResolution.applyClient] → write the client payload.
  /// [resolution] == [ConflictResolution.discardClient] → discard without writing.
  void resolveConflict(String itemId, ConflictResolution resolution) {
    _pausedIds.remove(itemId);
    final idx = _queue.indexWhere((i) => i.id == itemId);
    if (idx == -1) return;

    if (resolution == ConflictResolution.discardClient) {
      _queue.removeAt(idx);
      _statusController.add({itemId: false});
      debugPrint('[SyncManager] Manual conflict discarded for $itemId');
    } else {
      debugPrint('[SyncManager] Manual conflict: applying client version for $itemId');
      _processQueue();
    }
  }

  /// Trigger a sync attempt (e.g. when connectivity is restored).
  void triggerSync() => _processQueue();

  // ─── Private ───────────────────────────────────────────────────────────────

  Future<void> _processQueue() async {
    if (_isSyncing || _queue.isEmpty) return;
    _isSyncing = true;

    debugPrint('[SyncManager] Starting sync loop for ${_queue.length} item(s)');

    while (_queue.isNotEmpty) {
      final item = _queue.first;

      // Skip items paused for manual conflict resolution.
      if (_pausedIds.contains(item.id)) {
        debugPrint('[SyncManager] Skipping paused item ${item.id}');
        break;
      }

      try {
        final outcome = await _execute(item);

        if (outcome == _ExecuteOutcome.success) {
          _queue.removeAt(0);
          _statusController.add({item.id: true});
          debugPrint('[SyncManager] Synced ${item.id}');
        } else if (outcome == _ExecuteOutcome.conflictServerWins) {
          // Server won — revert the optimistic UI state.
          _queue.removeAt(0);
          _statusController.add({item.id: false});
        } else if (outcome == _ExecuteOutcome.conflictManual) {
          // Paused — do not advance the queue until resolved.
          _pausedIds.add(item.id);
          break;
        }
      } catch (e) {
        debugPrint('[SyncManager] Sync failed for ${item.id}: $e');

        if (++item.retryCount >= 5) {
          _queue.removeAt(0);
          _statusController.add({item.id: false});
          debugPrint('[SyncManager] Discarded ${item.id} after max retries');
        } else {
          break; // Back off; retry on next triggerSync call
        }
      }
    }

    _isSyncing = false;

    if (_queue.isNotEmpty && _pausedIds.length < _queue.length) {
      // There are still executable items — retry after back-off.
      Timer(const Duration(seconds: 30), _processQueue);
    }
  }

  Future<_ExecuteOutcome> _execute(SyncItem item) async {
    final client = Supabase.instance.client;

    switch (item.action) {
      case SyncAction.insert:
        await client.from(item.table).insert(item.payload);
        return _ExecuteOutcome.success;

      case SyncAction.update:
        return await _executeUpdate(client, item);

      case SyncAction.delete:
        final id = item.payload['id'] as String;
        await client.from(item.table).delete().eq('id', id);
        return _ExecuteOutcome.success;

      case SyncAction.rpc:
        await client.rpc(item.table, params: item.payload);
        return _ExecuteOutcome.success;
    }
  }

  Future<_ExecuteOutcome> _executeUpdate(
    SupabaseClient client,
    SyncItem item,
  ) async {
    final id = item.payload['id'] as String;

    // clientWins: write unconditionally without a round-trip pre-check.
    if (item.conflictPolicy == ConflictPolicy.clientWins ||
        item.serverUpdatedAtBaseline == null) {
      await client.from(item.table).update(item.payload).eq('id', id);
      return _ExecuteOutcome.success;
    }

    // For serverWins and manual: fetch current updated_at to detect conflict.
    final serverRows = await client
        .from(item.table)
        .select('updated_at')
        .eq('id', id)
        .limit(1);

    if (serverRows.isEmpty) {
      // Row no longer exists — treat as conflict (server deleted it).
      debugPrint('[SyncManager] Row ${item.table}/$id deleted on server; skipping update');
      _emitConflict(item, serverVersion: {}, isManual: item.conflictPolicy == ConflictPolicy.manual);
      return item.conflictPolicy == ConflictPolicy.manual
          ? _ExecuteOutcome.conflictManual
          : _ExecuteOutcome.conflictServerWins;
    }

    final serverUpdatedAt = DateTime.tryParse(
      (serverRows.first['updated_at'] as String?) ?? '',
    );
    final baseline = DateTime.tryParse(item.serverUpdatedAtBaseline!);

    final hasConflict = serverUpdatedAt != null &&
        baseline != null &&
        serverUpdatedAt.isAfter(baseline);

    if (!hasConflict) {
      await client.from(item.table).update(item.payload).eq('id', id);
      return _ExecuteOutcome.success;
    }

    // Conflict detected — fetch the full server row for the conflict event.
    final fullRows = await client.from(item.table).select().eq('id', id).limit(1);
    final serverVersion = fullRows.isNotEmpty
        ? Map<String, dynamic>.from(fullRows.first)
        : <String, dynamic>{};

    debugPrint(
      '[SyncManager] Conflict on ${item.table}/$id '
      '(server=${serverUpdatedAt.toIso8601String()} baseline=${item.serverUpdatedAtBaseline})',
    );

    _emitConflict(
      item,
      serverVersion: serverVersion,
      isManual: item.conflictPolicy == ConflictPolicy.manual,
    );

    return item.conflictPolicy == ConflictPolicy.manual
        ? _ExecuteOutcome.conflictManual
        : _ExecuteOutcome.conflictServerWins;
  }

  void _emitConflict(
    SyncItem item, {
    required Map<String, dynamic> serverVersion,
    required bool isManual,
  }) {
    _conflictController.add(SyncConflict(
      itemId: item.id,
      table: item.table,
      clientVersion: item.payload,
      serverVersion: serverVersion,
      policy: item.conflictPolicy,
    ));
  }
}

enum _ExecuteOutcome {
  success,
  conflictServerWins,
  conflictManual,
}
