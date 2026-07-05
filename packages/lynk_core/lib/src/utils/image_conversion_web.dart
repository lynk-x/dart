import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Re-encodes image bytes as WEBP via canvas. Returns the original
/// bytes/extension unchanged if the input isn't a recognized raster image
/// format, or if any step of the canvas pipeline fails.
Future<(Uint8List bytes, String ext)> convertImageToWebP(
  Uint8List bytes,
  String ext,
) async {
  final normalizedExt = ext.toLowerCase();
  if (normalizedExt == 'webp' ||
      !const {'png', 'jpg', 'jpeg', 'gif', 'bmp'}.contains(normalizedExt)) {
    return (bytes, ext);
  }

  try {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/$normalizedExt'),
    );
    final blobUrl = web.URL.createObjectURL(blob);

    try {
      final image = web.HTMLImageElement()..src = blobUrl;
      await image.decode().toDart;

      final canvas = web.HTMLCanvasElement()
        ..width = image.naturalWidth
        ..height = image.naturalHeight;
      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      ctx.drawImage(image, 0, 0);

      final webpBlob = await _canvasToBlob(canvas);
      if (webpBlob == null) return (bytes, ext);

      final arrayBuffer = await webpBlob.arrayBuffer().toDart;
      return (arrayBuffer.toDart.asUint8List(), 'webp');
    } finally {
      web.URL.revokeObjectURL(blobUrl);
    }
  } catch (_) {
    return (bytes, ext);
  }
}

Future<web.Blob?> _canvasToBlob(web.HTMLCanvasElement canvas) {
  final completer = Completer<web.Blob?>();
  canvas.toBlob(
    (web.Blob? blob) {
      completer.complete(blob);
    }.toJS,
    'image/webp',
    0.9.toJS,
  );
  return completer.future;
}
