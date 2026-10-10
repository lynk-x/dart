// Direct-to-R2 PUT with upload progress and a stall-based timeout (web/js/upload_tools.js).
// A fixed total timeout kills large videos that are still moving on a slow connection; this only
// gives up when no bytes have been sent for [stall].
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'retry.dart';

@JS('window.lynkUploadTools.putWithProgress')
external JSPromise<JSNumber> _jsPutWithProgress(
  JSString url,
  JSUint8Array bytes,
  JSString contentType,
  JSFunction onProgress,
  JSNumber stallMs,
);

/// PUTs [bytes] to the presigned [url] and returns the HTTP status code. [onProgress] gets 0.0–1.0.
/// A dropped or stalled connection throws [TransientFailure] so [retryTransient] can try again
/// with a fresh URL; the caller decides what a non-2xx status means.
Future<int> putBytesWithProgress(
  Uri url,
  Uint8List bytes,
  String contentType, {
  void Function(double fraction)? onProgress,
  Duration stall = const Duration(seconds: 30),
}) async {
  if (!kIsWeb) {
    final response = await http.put(url, headers: {'Content-Type': contentType}, body: bytes);
    return response.statusCode;
  }
  try {
    final status = await _jsPutWithProgress(
      url.toString().toJS,
      bytes.toJS,
      contentType.toJS,
      ((JSNumber fraction) => onProgress?.call(fraction.toDartDouble)).toJS,
      stall.inMilliseconds.toJS,
    ).toDart;
    return status.toDartInt;
  } catch (e) {
    throw TransientFailure('Upload interrupted (network lost or stalled)');
  }
}
