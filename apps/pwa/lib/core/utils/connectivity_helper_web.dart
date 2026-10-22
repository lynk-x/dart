import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Browser connectivity stream — emits true when online, false when offline.
/// Gated on dart.library.js_interop (see connectivity_helper.dart) so it is
/// selected under both JS and WASM web compile targets.
class ConnectivityHelper {
  /// Stream that emits true when online and false when offline.
  static Stream<bool> get onConnectivityChanged {
    late final StreamController<bool> controller;

    void onOnline(web.Event _) => controller.add(true);
    void onOffline(web.Event _) => controller.add(false);
    final onlineListener = onOnline.toJS;
    final offlineListener = onOffline.toJS;

    controller = StreamController<bool>.broadcast(
      onListen: () {
        web.window.addEventListener('online', onlineListener);
        web.window.addEventListener('offline', offlineListener);
      },
      onCancel: () {
        web.window.removeEventListener('online', onlineListener);
        web.window.removeEventListener('offline', offlineListener);
      },
    );

    return controller.stream;
  }
}
