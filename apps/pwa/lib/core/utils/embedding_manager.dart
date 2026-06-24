import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'package:lynk_x/core/sync/sync_item.dart';
import 'package:lynk_x/core/sync/sync_manager.dart';

class EmbeddingManager {
  EmbeddingManager._();
  static final instance = EmbeddingManager._();

  web.Worker? _worker;
  bool _isReady = false;

  final Set<String> _computingMessageIds = {};
  final Set<String> _syncingMessageIds = {};

  bool get isReady => _isReady;

  bool get _shouldPreventUnload {
    if (_computingMessageIds.isNotEmpty) return true;
    final isOnline = web.window.navigator.onLine;
    if (isOnline && _syncingMessageIds.isNotEmpty) return true;
    return false;
  }

  // Noise Filters
  static final Set<String> _noiseWords = {
    'lol', 'haha', 'lmao', 'test', 'yes', 'no', 'ok', 'hey', 'hi', 'bye'
  };
  static final RegExp _meaningfulContentRegex = RegExp(r'[a-zA-Z0-9\u00C0-\u00FF\u0100-\u017F]');
  static final RegExp _urlRegex = RegExp(r'^(https?:\/\/[^\s]+)$');

  static bool isNoiseMessage(String text) {
    final trimmed = text.trim().toLowerCase();
    
    // 1. Length Check
    if (trimmed.length < 10 || trimmed.split(RegExp(r'\s+')).length < 3) {
      return true;
    }
    
    // 2. Meaningful Content Check (ignore if only emojis/punctuation/noise symbols)
    if (!_meaningfulContentRegex.hasMatch(trimmed)) {
      return true;
    }

    // 3. Common Stop Words
    if (_noiseWords.contains(trimmed)) {
      return true;
    }

    // 4. URL Only
    if (_urlRegex.hasMatch(trimmed)) {
      return true;
    }

    return false;
  }

  // Check if network connection is Wi-Fi or Ethernet
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
    // Fallback: If NetworkInfo is not supported, default to true to allow loading
    return true;
  }

  void init() {
    if (_worker != null) return;

    if (!_isWifiConnection()) {
      debugPrint('[EmbeddingManager] Skipping client embedding: Not on Wi-Fi connection.');
      return;
    }

    try {
      // Register unload listener once to prevent tab closing during calculations
      web.window.addEventListener('beforeunload', ((web.Event event) {
        if (_shouldPreventUnload) {
          event.preventDefault();
          final beforeUnloadEvent = event as web.BeforeUnloadEvent;
          beforeUnloadEvent.returnValue = '';
        }
      }).toJS);

      // Listen to sync updates to remove items from our in-flight tracking list
      SyncManager.instance.statusStream.listen((statusMap) {
        for (final entry in statusMap.entries) {
          final key = entry.key;
          if (key.endsWith('_embedding')) {
            final msgId = key.replaceAll('_embedding', '');
            _syncingMessageIds.remove(msgId);
          }
        }
      });

      // Load Web Worker from PWA web folder root
      _worker = web.Worker('embedding.worker.js'.toJS);
      
      // Initialize the model
      _worker?.postMessage({'type': 'init'}.jsify());

      _worker?.onmessage = (web.MessageEvent event) {
        final dartData = event.data.dartify();
        if (dartData is Map) {
          final type = dartData['type'];
          if (type == 'ready') {
            _isReady = true;
            debugPrint('[EmbeddingManager] Web Worker embedding model loaded successfully.');
          } else if (type == 'progress') {
            debugPrint('[EmbeddingManager] Loading model ${dartData['file']}: ${(dartData['progress'] * 100).toStringAsFixed(1)}%');
          } else if (type == 'embed_result') {
            final List<dynamic> embedding = dartData['embedding'];
            final String msgId = dartData['msgId'];
            _computingMessageIds.remove(msgId);
            _syncingMessageIds.add(msgId);
            _uploadEmbedding(msgId, embedding.cast<double>());
          } else if (type == 'error') {
            final String? msgId = dartData['msgId'];
            if (msgId != null) {
              _computingMessageIds.remove(msgId);
            }
            debugPrint('[EmbeddingManager] Worker Error: ${dartData['error']}');
          }
        }
      }.toJS;
    } catch (e) {
      debugPrint('[EmbeddingManager] Failed to initialize worker: $e');
    }
  }

  void processMessage(String messageId, String text) {
    if (!_isReady) return;
    if (isNoiseMessage(text)) {
      debugPrint('[EmbeddingManager] Skipping embedding: message "$text" classified as noise.');
      return;
    }
    _computingMessageIds.add(messageId);
    _worker?.postMessage({
      'type': 'embed',
      'text': text,
      'msgId': messageId,
    }.jsify());
  }

  void _uploadEmbedding(String messageId, List<double> embedding) {
    debugPrint('[EmbeddingManager] Queueing embedding upload for message: $messageId');
    
    // Queue RPC upload through SyncManager to handle offline/retry scenarios safely
    SyncManager.instance.addWork(SyncItem(
      id: '${messageId}_embedding',
      table: 'update_my_chat_embedding', // API schema proxy function
      schema: 'api',
      action: SyncAction.rpc,
      payload: {
        'p_message_id': messageId,
        'p_embedding': embedding, // List<double> is converted to vector by Supabase SDK
      },
    ));
  }
}
