import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart';

typedef WorkerProgressCallback = void Function(String file, double progress);
typedef WorkerReadyCallback = void Function();
typedef WorkerResultCallback = void Function(List<double> embedding, String messageId);
typedef WorkerErrorCallback = void Function(String? messageId, String error);

class EmbeddingWorkerClient {
  final String workerPath;
  final WorkerProgressCallback? onProgress;
  final WorkerReadyCallback? onReady;
  final WorkerResultCallback? onResult;
  final WorkerErrorCallback? onError;

  web.Worker? _worker;
  bool _isReady = false;

  EmbeddingWorkerClient({
    required this.workerPath,
    this.onProgress,
    this.onReady,
    this.onResult,
    this.onError,
  });

  bool get isReady => _isReady;

  void init() {
    try {
      _worker = web.Worker(workerPath.toJS);
      _worker?.postMessage({'type': 'init'}.jsify());

      _worker?.onmessage = (web.MessageEvent event) {
        final dartData = event.data.dartify();
        if (dartData is Map) {
          final type = dartData['type'];
          if (type == 'ready') {
            _isReady = true;
            onReady?.call();
          } else if (type == 'progress') {
            final file = dartData['file'] as String? ?? '';
            final progress = (dartData['progress'] as num?)?.toDouble() ?? 0.0;
            onProgress?.call(file, progress);
          } else if (type == 'embed_result') {
            final embedding = (dartData['embedding'] as List<dynamic>).cast<double>();
            final msgId = dartData['msgId'] as String;
            onResult?.call(embedding, msgId);
          } else if (type == 'error') {
            final msgId = dartData['msgId'] as String?;
            final error = dartData['error'] as String? ?? 'Unknown error';
            onError?.call(msgId, error);
          }
        }
      }.toJS;
    } catch (e) {
      debugPrint('[EmbeddingWorkerClient] Failed to initialize: $e');
    }
  }

  void embed(String text, String messageId) {
    if (!_isReady || _worker == null) {
      throw StateError('Worker not initialized');
    }
    _worker?.postMessage({
      'type': 'embed',
      'text': text,
      'msgId': messageId,
    }.jsify());
  }

  void dispose() {
    _worker?.terminate();
    _worker = null;
    _isReady = false;
  }
}
