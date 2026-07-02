// dart.library.js_interop (NOT dart.library.html) is the correct guard here:
// dart.library.html evaluates to FALSE under dart2wasm compilation
// (`flutter build web --wasm`) even when running in a real browser, because
// dart:html itself is unsupported/unavailable under that compile target. A
// dart.library.html-gated conditional import would therefore silently select
// download_helper_stub.dart (the url_launcher/new-tab fallback) in a WASM
// production build, on every browser including Chrome — not just Safari.
// dart.library.js_interop is available under both the JS and Wasm web
// compile targets, so download_helper_web.dart (built on package:web +
// dart:js_interop, not dart:html) is correctly selected either way.
export 'download_helper_stub.dart'
    if (dart.library.js_interop) 'download_helper_web.dart';
