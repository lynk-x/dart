// Browser-side image downscaling (web/js/image_tools.js) for upload flows that shouldn't push
// multi-megabyte phone photos over metered connections.
import 'dart:js_interop';
import 'package:flutter/foundation.dart';

@JS('window.lynkImageTools.resizeToJpeg')
external JSPromise<JSUint8Array?> _jsResizeToJpeg(JSUint8Array bytes, JSNumber maxEdge, JSNumber quality);

/// Returns [bytes] scaled to fit within [maxEdge] pixels and re-encoded as JPEG, or null when
/// the image can't be decoded (or off web) — callers should then keep the original bytes.
Future<Uint8List?> resizeImageToJpeg(
  Uint8List bytes, {
  required int maxEdge,
  double quality = 0.85,
}) async {
  if (!kIsWeb) return null;
  try {
    final result = await _jsResizeToJpeg(bytes.toJS, maxEdge.toJS, quality.toJS).toDart;
    return result?.toDart;
  } catch (e) {
    debugPrint('[ImageResizer] resize failed: $e');
    return null;
  }
}

@JS('window.lynkImageTools.videoPosterJpeg')
external JSPromise<JSUint8Array?> _jsVideoPosterJpeg(JSAny source, JSNumber maxEdge, JSNumber quality);

/// A JPEG still taken from a video, for its grid thumbnail. Pass [url] (a blob: URL — avoids
/// copying the video) or [bytes]. Null when the browser can't decode the video or off web.
Future<Uint8List?> extractVideoPoster({
  String? url,
  Uint8List? bytes,
  required int maxEdge,
  double quality = 0.75,
}) async {
  if (!kIsWeb || (url == null && bytes == null)) return null;
  try {
    final JSAny source = url != null ? url.toJS : bytes!.toJS;
    final result = await _jsVideoPosterJpeg(source, maxEdge.toJS, quality.toJS).toDart;
    return result?.toDart;
  } catch (e) {
    debugPrint('[ImageResizer] video poster failed: $e');
    return null;
  }
}
