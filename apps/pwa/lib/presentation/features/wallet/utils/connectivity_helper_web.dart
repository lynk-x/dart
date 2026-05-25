// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

class ConnectivityHelper {
  /// Stream that emits true when online and false when offline.
  static Stream<bool> get onConnectivityChanged {
    final controller = StreamController<bool>.broadcast();
    
    // Listen to browser-native window online/offline events
    html.window.onOnline.listen((_) => controller.add(true));
    html.window.onOffline.listen((_) => controller.add(false));
    
    return controller.stream;
  }
}
