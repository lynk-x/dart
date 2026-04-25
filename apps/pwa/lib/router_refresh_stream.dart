import 'dart:async';
import 'package:flutter/foundation.dart';

/// Bridges multiple [Stream]s into a single [ChangeNotifier] for GoRouter.
class GoRouterRefreshStream extends ChangeNotifier {
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  GoRouterRefreshStream(List<Stream<dynamic>> streams) {
    for (final stream in streams) {
      _subscriptions.add(
        stream.asBroadcastStream().listen((_) => notifyListeners()),
      );
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }
}
