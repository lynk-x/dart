// dart.library.js_interop (NOT dart.library.html) is the correct guard: see
// core/utils/download_helper.dart for the full explanation — dart.library.html
// evaluates to FALSE under dart2wasm ('flutter build web --wasm') even in a
// real browser, since dart:html is unsupported under that compile target.
// A dart.library.html-gated conditional import silently selected the stub
// (Stream.empty() — connectivity monitoring entirely disabled, so wallet
// balance realtime never resubscribed after a network drop) in every WASM
// production build.
export 'connectivity_helper_stub.dart'
    if (dart.library.js_interop) 'connectivity_helper_web.dart';
