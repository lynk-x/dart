// Retry-with-backoff for flaky mobile networks. Only transient failures are retried (timeouts,
// dropped connections, 5xx/429); anything else (RLS denial, bad input) fails immediately so the
// user isn't left waiting on an error that can't fix itself.
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown by callers to mark an HTTP response (e.g. an R2 5xx) as worth retrying.
class TransientFailure implements Exception {
  final String message;
  const TransientFailure(this.message);

  @override
  String toString() => message;
}

/// True for errors that a later attempt could plausibly succeed after.
bool isTransientError(Object e) {
  if (e is TimeoutException || e is http.ClientException || e is TransientFailure) return true;
  if (e is FunctionException) return e.status >= 500 || e.status == 429;
  return false;
}

/// Runs [op], retrying transient failures up to [attempts] times in total, waiting
/// [baseDelay] * attempt between tries (2 s, 4 s by default). Rethrows the last error.
Future<T> retryTransient<T>(
  Future<T> Function() op, {
  int attempts = 3,
  Duration baseDelay = const Duration(seconds: 2),
  bool Function(Object error)? isTransient,
}) async {
  final shouldRetry = isTransient ?? isTransientError;
  for (var attempt = 1;; attempt++) {
    try {
      return await op();
    } catch (e) {
      if (attempt >= attempts || !shouldRetry(e)) rethrow;
      await Future<void>.delayed(baseDelay * attempt);
    }
  }
}
