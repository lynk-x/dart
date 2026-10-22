import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sync_item.dart';
import '../utils/connectivity_helper.dart';

/// Orchestrates background synchronisation for the PWA — queues actions and
/// retries them when network returns, enabling optimistic UI.
///
/// ## Conflict Detection (UPDATE actions only)
///
/// UPDATEs use rowcount-based optimistic concurrency: the write carries the
/// client's observed `updated_at` as a guard clause (`WHERE id = $1 AND
/// updated_at = $2`), and the rowcount tells us whether the write applied.
///
///   • [ConflictPolicy.serverWins] — if the guard fails (rowcount 0), skip
///     the write, emit `{id: false}` on [statusStream] (cubit reverts
///     optimistic state), and emit a [SyncConflict] on [conflictStream].
///
///   • [ConflictPolicy.clientWins] — try the guarded write; on failure
///     re-issue it unguarded (client always wins, now informed by server
///     state). No conflict event is emitted.
///
///   • [ConflictPolicy.manual]     — pause the item in the queue without
///     advancing and emit a [SyncConflict]. Nothing is written until the
///     caller invokes [resolveConflict].
///
/// INSERT and DELETE actions never trigger conflict detection. INSERTs that
/// hit a unique constraint (23505) are dropped as duplicates.
///
/// ## Idempotency
///
/// Every [SyncItem] carries a client-generated [SyncItem.idempotencyKey]
/// (UUID v4). The server dedupes on `(user_id, idempotencyKey)`, so a crash
/// between [addWork] and persist, or a duplicate cubit call, can never queue
/// the same logical action twice.
///
/// ## Batching
///
/// Consecutive `rpc` items with identical `(table, schema, action)` are
/// drained into a single server call (up to [_kBatchSize]) instead of one
/// HTTP round-trip per item. This is the main win for embedding traffic,
/// which is one RPC per message.
///
/// INSERT/UPDATE/DELETE are row-scoped and are not batched.
class SyncManager {
  SyncManager._() {
    _initConnectivityListener();
  }
  static final instance = SyncManager._();

  static const String _kQueueStorageKey = 'sync_manager_queue';

  /// Maximum number of same-shape RPC items drained into one batch call.
  static const int _kBatchSize = 50;

  /// Per-item retry cap. Beyond this the item is dropped and the cubit is
  /// told to revert — five attempts covers transient network blips without
  /// burning forever on a permanently-denied write.
  static const int _kMaxRetries = 5;

  final Queue<SyncItem> _queue = Queue();

  /// Item IDs paused pending manual conflict resolution.
  final Set<String> _pausedIds = {};

  bool _isSyncing = false;
  bool _isInitialized = false;

  /// Set by the watchdog when it detects the queue has been actively locked
  /// past the watchdog window. The running loop checks this between items and
  /// bails out so the tail timer can reschedule — never by flipping
  /// _isSyncing and calling _processQueue directly, which would spawn a
  /// second concurrent loop on the same _queue list.
  bool _stuck = false;

  /// Exposes the current number of pending items queued for sync.
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);

  StreamSubscription<bool>? _connectivitySub;

  /// `{itemId: success}` broadcast — consumed by cubits to confirm or revert
  /// their optimistic state.
  final _statusController = StreamController<Map<String, bool>>.broadcast();
  Stream<Map<String, bool>> get statusStream => _statusController.stream;

  /// Conflict events — consumed by UI layers that need to present a resolution
  /// dialog. Only emitted for [ConflictPolicy.serverWins] and
  /// [ConflictPolicy.manual].
  final _conflictController = StreamController<SyncConflict>.broadcast();
  Stream<SyncConflict> get conflictStream => _conflictController.stream;

  void _initConnectivityListener() {
    _connectivitySub =
        ConnectivityHelper.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        debugPrint(
            '[SyncManager] Connectivity restored, triggering queue processing immediately.');
        triggerSync();
      }
    });
  }

  /// Loads any queue items persisted from a previous session (e.g. actions
  /// still pending when the app was closed or lost connectivity) and resumes
  /// processing. Call once at app startup, before any [addWork] calls.
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kQueueStorageKey);
      if (jsonStr == null || jsonStr.isEmpty) return;

      final decoded = jsonDecode(jsonStr) as List;
      _queue.addAll(
        decoded
            .map((e) => SyncItem.fromMap(Map<String, dynamic>.from(e as Map))),
      );
      _updatePendingCount();
      debugPrint(
          '[SyncManager] Restored ${_queue.length} queued item(s) from previous session.');
      _processQueue();
    } catch (e, stack) {
      debugPrint(
          '[SyncManager] init() failed to load persisted queue: $e\n$stack');
    }
  }

  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_queue.isEmpty) {
        await prefs.remove(_kQueueStorageKey);
        return;
      }
      final encoded = _queue.map((item) => item.toMap()).toList();
      await prefs.setString(_kQueueStorageKey, jsonEncode(encoded));
    } catch (e, stack) {
      debugPrint('[SyncManager] Failed to persist queue: $e\n$stack');
    }
  }

  /// Maximum duration allowed for an individual sync item's network round-trip.
  static const Duration _kExecutionTimeout = Duration(seconds: 20);

  /// Watchdog timeout limit: if queue processing is actively locked for longer
  /// than this duration without completing, the watchdog forcibly clears the
  /// syncing lock and reschedules to self-heal hung connections.
  static const Duration _kQueueWatchdogTimeout = Duration(seconds: 45);

  Timer? _queueWatchdogTimer;

  void dispose() {
    _queueWatchdogTimer?.cancel();
    _connectivitySub?.cancel();
    _statusController.close();
    _conflictController.close();
    pendingCountNotifier.dispose();
  }

  /// Add a pending action to the queue.
  /// The calling cubit should have already applied its optimistic state update.
  void addWork(SyncItem item) {
    _queue.add(item);
    _updatePendingCount();
    _persistQueue();
    _processQueue();
  }

  /// Check if an item is currently queued for syncing.
  bool isQueued(String id) {
    return _queue.any((item) => item.id == id);
  }

  /// Resolve a [ConflictPolicy.manual] conflict that was previously paused.
  ///
  /// [resolution] == [ConflictResolution.applyClient] → write the client payload.
  /// [resolution] == [ConflictResolution.discardClient] → discard without writing.
  void resolveConflict(String itemId, ConflictResolution resolution) {
    _pausedIds.remove(itemId);

    if (resolution == ConflictResolution.discardClient) {
      // Queue has no indexWhere/removeAt, so rebuild without the item.
      final remaining = _queue.where((i) => i.id != itemId).toList();
      _queue.clear();
      _queue.addAll(remaining);
      _updatePendingCount();
      _persistQueue();
      _statusController.add({itemId: false});
    } else {
      // Re-arm the watchdog: the resumed item may hang, and without this
      // the only protection is the per-item timeout — which only fires if
      // _processQueue's own watchdog was armed, and it isn't here.
      _stuck = false;
      _armQueueWatchdog();
      _processQueue();
    }
  }

  /// Trigger a sync attempt (e.g. when connectivity is restored).
  void triggerSync() => _processQueue();

  void _updatePendingCount() {
    if (pendingCountNotifier.value != _queue.length) {
      pendingCountNotifier.value = _queue.length;
    }
  }

  // ─── Private ───────────────────────────────────────────────────────────────

  /// Arms an active watchdog timer to prevent [_isSyncing] from remaining permanently
  /// stuck in true if an unhandled asynchronous hang occurs (e.g., interrupted TCP handshake
  /// during mobile network transitions).
  void _armQueueWatchdog() {
    _queueWatchdogTimer?.cancel();
    _queueWatchdogTimer = Timer(_kQueueWatchdogTimeout, () {
      if (_isSyncing) {
        _stuck = true;
        debugPrint(
          '[SyncManager] Watchdog tripped: sync queue stuck for >${_kQueueWatchdogTimeout.inSeconds}s. '
          'Flagged stuck; running loop will bail and reschedule on its next iteration.',
        );
      }
    });
  }

  void _disarmQueueWatchdog() {
    _queueWatchdogTimer?.cancel();
    _queueWatchdogTimer = null;
  }

  Future<void> _processQueue() async {
    if (_isSyncing || _queue.isEmpty) return;
    _isSyncing = true;
    _armQueueWatchdog();

    try {
      while (_queue.isNotEmpty && !_stuck) {
        final item = _queue.first;

        // Skip items paused for manual conflict resolution.
        if (_pausedIds.contains(item.id)) {
          break;
        }

        try {
          // Batch consecutive same-shape RPC items into one server call.
          // This is the main win for embedding traffic, which is one RPC per
          // message — 50 messages become one round-trip instead of fifty.
          final batch = _drainBatch(item);
          if (batch.length > 1) {
            final results = await _executeBatch(batch).timeout(
              _kExecutionTimeout,
              onTimeout: () => throw TimeoutException(
                'Batch sync timed out for ${batch.length} item(s) on '
                '${item.table}/${item.schema} after ${_kExecutionTimeout.inSeconds}s',
              ),
            );

            _stuck = false;
            _armQueueWatchdog();

            // Re-queue failed items with bumped retry counts. They're already
            // drained, so without this they'd be silently lost — and re-adding
            // at the head means the next iteration re-drains them, which is
            // why we cap at 5 like single items and back off otherwise.
            final failed = <SyncItem>[];
            for (final b in batch) {
              final ok = results[b.id] ?? false;
              if (!ok) failed.add(b);
              _statusController.add({b.id: ok});
            }
            if (failed.isNotEmpty) {
              for (final f in failed) {
                final bumped = f.copyWith(retryCount: f.retryCount + 1);
                if (bumped.retryCount >= _kMaxRetries) {
                  debugPrint(
                    '[SyncManager] Discarded ${f.id} after max retries (batch)',
                  );
                } else {
                  _queue.addFirst(bumped);
                }
              }
              _updatePendingCount();
              _persistQueue();
              break; // Back off; retry on next triggerSync call or timer
            }
            _updatePendingCount();
            _persistQueue();
            continue;
          }

          // Guard each database mutation with a hard timeout to avoid hung HTTP sockets
          final outcome = await _execute(item).timeout(
            _kExecutionTimeout,
            onTimeout: () => throw TimeoutException(
              'Sync execution timed out for ${item.table}/${item.id} after ${_kExecutionTimeout.inSeconds}s',
            ),
          );

          // Reset watchdog window after each item successfully completes
          _stuck = false;
          _armQueueWatchdog();

          if (outcome == _ExecuteOutcome.success) {
            _queue.removeFirst();
            _updatePendingCount();
            _persistQueue();
            _statusController.add({item.id: true});
          } else if (outcome == _ExecuteOutcome.duplicate) {
            // Row already exists server-side — drop the queued insert and
            // tell the cubit to revert its optimistic state.
            _queue.removeFirst();
            _updatePendingCount();
            _persistQueue();
            _statusController.add({item.id: false});
          } else if (outcome == _ExecuteOutcome.conflictServerWins) {
            // Server won — revert the optimistic UI state.
            _queue.removeFirst();
            _updatePendingCount();
            _persistQueue();
            _statusController.add({item.id: false});
          } else if (outcome == _ExecuteOutcome.conflictManual) {
            // Paused — do not advance the queue until resolved.
            _pausedIds.add(item.id);
            break;
          }
        } catch (e) {
          debugPrint('[SyncManager] Sync failed for ${item.id}: $e');

          // Queue has no indexed setter, so remove-then-addFirst (both O(1))
          // to bump the retry count on the head item.
          final head = _queue.removeFirst();
          final bumped = head.copyWith(retryCount: head.retryCount + 1);
          _queue.addFirst(bumped);
          if (bumped.retryCount >= _kMaxRetries) {
            _queue.removeFirst();
            _updatePendingCount();
            _persistQueue();
            _statusController.add({item.id: false});
            debugPrint('[SyncManager] Discarded ${item.id} after max retries');
          } else {
            _persistQueue();
            // Back off — the tail timer reschedules. A `continue` here would
            // re-process the same item immediately (tight retry loop); a
            // `break` lets the queue advance on the next triggerSync call.
            break;
          }
        }
      }
    } finally {
      _disarmQueueWatchdog();
      _isSyncing = false;
    }

    // Only schedule a retry if the head of the queue is actually retryable.
    // A paused (manual-conflict) item at the head would otherwise re-arm a
    // 1-second timer forever — the loop breaks on it, the tail schedules, and
    // nothing is ever resolved until the caller calls resolveConflict.
    if (_queue.isNotEmpty && !_pausedIds.contains(_queue.first.id)) {
      final retryCount = _queue.first.retryCount;
      final backoffSeconds = (1 << retryCount).clamp(1, 30);
      debugPrint(
          '[SyncManager] Scheduling retry in ${backoffSeconds}s (attempt #$retryCount)');
      Timer(Duration(seconds: backoffSeconds), _processQueue);
    }
  }

  Future<_ExecuteOutcome> _execute(SyncItem item) async {
    final client = Supabase.instance.client;

    switch (item.action) {
      case SyncAction.insert:
        try {
          var query = client.from(item.table);
          if (item.schema != null) {
            query = client.schema(item.schema!).from(item.table);
          }
          await query.insert(item.payload);
          return _ExecuteOutcome.success;
        } on PostgrestException catch (e) {
          if (e.code == '23505') {
            // A unique violation means the row already exists. This is NOT a
            // success: the pre-existing row may differ from our payload, so
            // the cubit's optimistic state must be reverted, not confirmed.
            debugPrint(
              '[SyncManager] Duplicate key (23505) on ${item.table}/${item.id}; '
              'discarding queued insert so caller can revert optimistic state.',
            );
            return _ExecuteOutcome.duplicate;
          }
          debugPrint(
            '[SyncManager] PostgrestException on ${item.table}/${item.id}: '
            'code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}',
          );
          rethrow;
        }

      case SyncAction.update:
        return await _executeUpdate(client, item);

      case SyncAction.delete:
        final id = item.payload['id'] as String;
        var query = client.from(item.table);
        if (item.schema != null) {
          query = client.schema(item.schema!).from(item.table);
        }
        var del = query.delete().eq('id', id);
        if (item.partitionKeyName != null && item.partitionKeyValue != null) {
          del = del.eq(item.partitionKeyName!, item.partitionKeyValue!);
        }
        await del;
        return _ExecuteOutcome.success;

      case SyncAction.rpc:
        await client.schema('api').rpc(item.table, params: item.payload);
        return _ExecuteOutcome.success;
    }
  }

  Future<_ExecuteOutcome> _executeUpdate(
    SupabaseClient client,
    SyncItem item,
  ) async {
    final id = item.payload['id'] as String;

    // No baseline → nothing to guard against; write unconditionally. This is
    // the old clientWins fast path, kept for items that never observed a
    // server row (INSERT-then-UPDATE sequences, etc.).
    if (item.serverUpdatedAtBaseline == null) {
      return _applyUpdate(client, item);
    }

    // Rowcount-based optimistic concurrency: the UPDATE itself carries the
    // guard clause `WHERE id = $1 AND updated_at = $2`, so the rowcount
    // tells us whether the write applied — one HTTP call instead of a
    // select-then-update, and no TOCTOU window between the two.
    final response = await _guardedUpdate(client, item);
    final applied = response.count > 0;
    if (applied) return _ExecuteOutcome.success;

    // Guard failed — another client wrote this row after we read it.
    switch (item.conflictPolicy) {
      case ConflictPolicy.clientWins:
        // Re-issue unguarded: client intent is authoritative, but we now
        // know the server state moved, so log it.
        debugPrint(
          '[SyncManager] clientWins re-assert on ${item.table}/$id '
          '(server row changed since baseline)',
        );
        return _applyUpdate(client, item);

      case ConflictPolicy.serverWins:
        _emitConflict(
          item,
          serverVersion: await _fetchServerRow(client, item),
          isManual: false,
        );
        return _ExecuteOutcome.conflictServerWins;

      case ConflictPolicy.manual:
        _emitConflict(
          item,
          serverVersion: await _fetchServerRow(client, item),
          isManual: true,
        );
        return _ExecuteOutcome.conflictManual;
    }
  }

  /// Applies the guarded UPDATE (`WHERE id = $1 AND updated_at = $2`).
  Future<PostgrestResponse> _guardedUpdate(
    SupabaseClient client,
    SyncItem item,
  ) async {
    final id = item.payload['id'] as String;
    final baseline = item.serverUpdatedAtBaseline!;
    var query = client.from(item.table);
    if (item.schema != null) query = client.schema(item.schema!).from(item.table);
    var upd = query
        .update(item.payload)
        .eq('id', id)
        .eq('updated_at', baseline);
    if (item.partitionKeyName != null && item.partitionKeyValue != null) {
      upd = upd.eq(item.partitionKeyName!, item.partitionKeyValue!);
    }
    return await upd;
  }

  /// Applies an unguarded UPDATE.
  Future<_ExecuteOutcome> _applyUpdate(
    SupabaseClient client,
    SyncItem item,
  ) async {
    final id = item.payload['id'] as String;
    var query = client.from(item.table);
    if (item.schema != null) query = client.schema(item.schema!).from(item.table);
    var upd = query.update(item.payload).eq('id', id);
    if (item.partitionKeyName != null && item.partitionKeyValue != null) {
      upd = upd.eq(item.partitionKeyName!, item.partitionKeyValue!);
    }
    await upd;
    return _ExecuteOutcome.success;
  }

  /// Fetches the current server row for conflict events.
  Future<Map<String, dynamic>> _fetchServerRow(
    SupabaseClient client,
    SyncItem item,
  ) async {
    final id = item.payload['id'] as String;
    var fullRowsQuery = client.from(item.table);
    if (item.schema != null) {
      fullRowsQuery = client.schema(item.schema!).from(item.table);
    }
    var full = fullRowsQuery.select().eq('id', id);
    if (item.partitionKeyName != null && item.partitionKeyValue != null) {
      full = full.eq(item.partitionKeyName!, item.partitionKeyValue!);
    }
    final fullRows = await full.limit(1);
    return fullRows.isNotEmpty
        ? Map<String, dynamic>.from(fullRows.first)
        : <String, dynamic>{};
  }

  /// Drains up to [_kBatchSize] consecutive same-shape `rpc` items from the
  /// head of the queue, removing them. Returns a single-item list when the
  /// head isn't batchable, so callers can fall back to the per-item path.
  List<SyncItem> _drainBatch(SyncItem head) {
    if (head.action != SyncAction.rpc) return [head];
    final batch = <SyncItem>[];
    while (_queue.isNotEmpty && batch.length < _kBatchSize) {
      final next = _queue.first;
      if (next.action != SyncAction.rpc) break;
      if (next.table != head.table || next.schema != head.schema) break;
      batch.add(_queue.removeFirst());
    }
    return batch;
  }

  /// Executes one batched RPC call and returns `{itemId: ok}` per item.
  /// The server-side batch endpoint must be idempotent and return a list of
  /// results aligned with the input order. On any error every item is
  /// reported as failed — the caller re-queues with bumped retry counts.
  Future<Map<String, bool>> _executeBatch(List<SyncItem> items) async {
    final client = Supabase.instance.client;
    final batchName = 'batch_${items.first.table}';
    final payload = {
      'items': items
          .map((i) => {
                'idempotency_key': i.idempotencyKey,
                ...i.payload,
              })
          .toList(),
    };
    try {
      final response =
          await client.schema('api').rpc(batchName, params: payload);
      final rows = (response as List?) ?? const [];
      final results = <String, bool>{};
      for (var i = 0; i < items.length; i++) {
        final ok = i < rows.length && rows[i] is Map
            ? (rows[i]['ok'] as bool?) ?? false
            : false;
        results[items[i].id] = ok;
      }
      return results;
    } catch (e) {
      debugPrint(
        '[SyncManager] Batch $batchName failed for ${items.length} item(s): $e',
      );
      return {for (final i in items) i.id: false};
    }
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
  duplicate,
  conflictServerWins,
  conflictManual,
}
