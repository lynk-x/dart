import 'dart:async';
import 'package:flutter/foundation.dart';

/// Bridges a [Stream] into a [ChangeNotifier] that GoRouter can listen to.
///
/// GoRouter's [refreshListenable] accepts a [Listenable]. By wrapping the
/// Supabase auth state stream, the router re-evaluates its [redirect] function
/// every time the auth state changes — eliminating the race condition where
/// [Supabase.instance.client.auth.currentSession] returns null during the
/// initial asynchronous session hydration from secure storage.
///
/// Usage:
/// ```dart
/// final GoRouter router = GoRouter(
///   refreshListenable: GoRouterRefreshStream(
///     Supabase.instance.client.auth.onAuthStateChange,
///   ),
///   redirect: (context, state) { ... },
/// );
/// ```
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    // Immediately notify once so the initial redirect fires with the correct
    // session state after Supabase has finished restoring from secure storage.
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
