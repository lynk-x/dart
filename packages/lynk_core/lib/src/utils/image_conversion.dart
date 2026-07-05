// Non-web platforms: no canvas available to re-encode with, so uploads
// keep their original bytes/extension unchanged.
export 'image_conversion_stub.dart'
    if (dart.library.js_interop) 'image_conversion_web.dart';
