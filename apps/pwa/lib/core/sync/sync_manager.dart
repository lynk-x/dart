import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sync_item.dart';

/// SyncManager
/// Orchestrates the background synchronization for the PWA.
/// Enables "Optimistic UI" by queuing actions and retrying them when network returns.
class SyncManager {
  SyncManager._();
  static final instance = SyncManager._();

  final List<SyncItem> _queue = [];
  bool _isSyncing = false;
  
  // Stream to notify UI of sync completion (id -> success)
  final _statusController = StreamController<Map<String, bool>>.broadcast();
  Stream<Map<String, bool>> get statusStream => _statusController.stream;

  /// Add an action to the sync queue.
  /// The UI should update optimistically before calling this.
  void addWork(SyncItem item) {
    debugPrint('[SyncManager] Adding work: ${item.id} on ${item.table}');
    _queue.add(item);
    _processQueue();
  }

  /// Attempts to empty the queue.
  Future<void> _processQueue() async {
    if (_isSyncing || _queue.isEmpty) return;
    _isSyncing = true;

    debugPrint('[SyncManager] Starting sync loop for ${_queue.length} items');

    while (_queue.isNotEmpty) {
      final item = _queue.first;
      
      try {
        await _execute(item);
        
        // Success: remove and notify
        _queue.removeAt(0);
        _statusController.add({item.id: true});
        debugPrint('[SyncManager] Successfully synced ${item.id}');
      } catch (e) {
        debugPrint('[SyncManager] Sync failed for ${item.id}: $e');
        
        // If it's a persistent error or we've retried too much, discard
        if (++item.retryCount >= 5) {
          _queue.removeAt(0);
          _statusController.add({item.id: false});
          debugPrint('[SyncManager] Discarding ${item.id} after maximum retries');
        } else {
          // Break and retry later (exponential backoff could go here)
          break;
        }
      }
    }

    _isSyncing = false;
    
    // If there's still work, schedule another check in 30s
    if (_queue.isNotEmpty) {
      Timer(const Duration(seconds: 30), _processQueue);
    }
  }

  Future<void> _execute(SyncItem item) async {
    final client = Supabase.instance.client;
    
    switch (item.action) {
      case SyncAction.insert:
        await client.from(item.table).insert(item.payload);
        break;
      case SyncAction.update:
        // Assume 'id' is in payload for updates
        final id = item.payload['id'];
        await client.from(item.table).update(item.payload).eq('id', id);
        break;
      case SyncAction.delete:
        final id = item.payload['id'];
        await client.from(item.table).delete().eq('id', id);
        break;
      case SyncAction.rpc:
        await client.rpc(item.table, params: item.payload);
        break;
    }
  }

  /// Global trigger to attempt a sync (e.g., when net returns)
  void triggerSync() => _processQueue();
}
