import 'dart:typed_data';

/// Non-web platforms: no canvas available, return the bytes/extension
/// unchanged. Native image compression is a separate concern (not scoped
/// here) and would use a plugin like flutter_image_compress if ever needed.
Future<(Uint8List bytes, String ext)> convertImageToWebP(
  Uint8List bytes,
  String ext,
) async {
  return (bytes, ext);
}
