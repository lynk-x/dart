import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'package:lynk_x/core/sync/sync_item.dart';
import 'package:lynk_x/core/sync/sync_manager.dart';
import 'package:lynk_x/core/utils/embedding_noise_filter.dart';
import 'package:lynk_x/core/utils/embedding_worker_client.dart';
import 'package:lynk_x/core/utils/i_embedding_service.dart';

/// Computes message vector embeddings client-side via a Web Worker (ONNX model)
/// and synchronizes them to Supabase via [SyncManager].
///
/// Implemented as a singleton to preserve worker state and prevent redundant
/// multi-megabyte model downloads in memory.
class EmbeddingManager implements IEmbeddingService {
  EmbeddingManager._();
  static final instance = EmbeddingManager._();

  EmbeddingWorkerClient? _workerClient;
  StreamSubscription<Map<String, bool>>? _statusSub;
  web.EventListener? _beforeUnloadListener;
  bool _isReady = false;
  bool _isEnabled = false;

  final Set<String> _computingMessageIds = {};
  final Set<String> _syncingMessageIds = {};

  /// Whether the background ONNX Web Worker is initialized and ready to compute embeddings.
  @override
  bool get isReady => _isReady;

  bool get _shouldPreventUnload {
    if (_computingMessageIds.isNotEmpty) return true;
    final isOnline = web.window.navigator.onLine;
    if (isOnline && _syncingMessageIds.isNotEmpty) return true;
    return false;
  }

  bool _isWifiConnection() {
    try {
      final navigatorObj = web.window.navigator as JSObject;
      if (navigatorObj.hasProperty('connection'.toJS).toDart) {
        final connection = navigatorObj.getProperty('connection'.toJS) as JSObject?;
        if (connection != null && connection.hasProperty('type'.toJS).toDart) {
          final String? type = (connection.getProperty('type'.toJS) as JSString?)?.toDart;
          if (type != null) {
            return type == 'wifi' || type == 'ethernet';
          }
        }
      }
    } catch (_) {}
    return true;
  }

  @override
  void init({bool isEnabled = true}) {
    _isEnabled = isEnabled;
    if (!isEnabled) {
      return;
    }

    if (_workerClient != null) return;

    if (!_isWifiConnection()) {
      return;
    }

    try {
      _beforeUnloadListener = ((web.Event event) {
        if (_shouldPreventUnload) {
          event.preventDefault();
          final beforeUnloadEvent = event as web.BeforeUnloadEvent;
          beforeUnloadEvent.returnValue = '';
        }
      }).toJS;
      web.window.addEventListener('beforeunload', _beforeUnloadListener);

      _statusSub?.cancel();
      _statusSub = SyncManager.instance.statusStream.listen((statusMap) {
        for (final entry in statusMap.entries) {
          final key = entry.key;
          if (key.endsWith('_embedding')) {
            final msgId = key.replaceAll('_embedding', '');
            _syncingMessageIds.remove(msgId);
          }
        }
      });

      _workerClient = EmbeddingWorkerClient(
        workerPath: 'embedding.worker.js',
        onReady: () {
          _isReady = true;
        },
        onProgress: (file, progress) {},
        onResult: (embedding, msgId) {
          _computingMessageIds.remove(msgId);
          _syncingMessageIds.add(msgId);
          _uploadEmbedding(msgId, embedding);
        },
        onError: (msgId, error) {
          if (msgId != null) {
            _computingMessageIds.remove(msgId);
            debugPrint('[EmbeddingManager] Worker Error for $msgId: $error');
          } else {
            debugPrint('[EmbeddingManager] Worker Error: $error');
          }
        },
      );

      _workerClient!.init();
    } catch (e) {
      debugPrint('[EmbeddingManager] Failed to initialize worker: $e');
    }
  }

  /// Terminates the Web Worker and clears the in-flight tracking sets.
  /// Safe to call from app teardown; subsequent [processMessage] calls are
  /// no-ops until [init] is called again.
  void dispose() {
    if (_beforeUnloadListener != null) {
      web.window.removeEventListener('beforeunload', _beforeUnloadListener);
      _beforeUnloadListener = null;
    }
    _statusSub?.cancel();
    _statusSub = null;
    _workerClient?.dispose();
    _workerClient = null;
    _isReady = false;
    _computingMessageIds.clear();
    _syncingMessageIds.clear();
  }

  @override
  void processMessage(String messageId, String text) {
    if (!_isEnabled || !_isReady) return;
    if (EmbeddingNoiseFilter.isNoise(text)) {
      return;
    }
    if (_computingMessageIds.contains(messageId)) return;

    _computingMessageIds.add(messageId);
    try {
      _workerClient?.embed(text, messageId);
    } catch (e) {
      _computingMessageIds.remove(messageId);
      debugPrint('[EmbeddingManager] Failed to queue embedding: $e');
    }
  }

  void _uploadEmbedding(String messageId, List<double> embedding) {

    SyncManager.instance.addWork(SyncItem(
      id: '${messageId}_embedding',
      table: 'update_my_chat_embedding',
      schema: 'api',
      action: SyncAction.rpc,
      payload: {
        'p_message_id': messageId,
        'p_embedding': embedding,
      },
    ));
  }
}
