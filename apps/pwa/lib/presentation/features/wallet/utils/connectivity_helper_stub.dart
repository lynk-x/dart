class ConnectivityHelper {
  /// Stream that emits true when online and false when offline.
  static Stream<bool> get onConnectivityChanged => const Stream.empty();
}
