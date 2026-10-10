import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lynk_x/core/utils/retry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const noDelay = Duration.zero;

  test('returns immediately on success without retrying', () async {
    var calls = 0;
    final result = await retryTransient(() async {
      calls++;
      return 'ok';
    }, baseDelay: noDelay);
    expect(result, 'ok');
    expect(calls, 1);
  });

  test('retries transient failures and succeeds', () async {
    var calls = 0;
    final result = await retryTransient(() async {
      calls++;
      if (calls < 3) throw TimeoutException('slow');
      return 'ok';
    }, baseDelay: noDelay);
    expect(result, 'ok');
    expect(calls, 3);
  });

  test('gives up after the attempt limit and rethrows the last error', () async {
    var calls = 0;
    await expectLater(
      retryTransient(() async {
        calls++;
        throw const TransientFailure('R2 HTTP 503');
      }, attempts: 3, baseDelay: noDelay),
      throwsA(isA<TransientFailure>()),
    );
    expect(calls, 3);
  });

  test('does not retry permanent errors', () async {
    var calls = 0;
    await expectLater(
      retryTransient(() async {
        calls++;
        throw const PostgrestException(message: 'new row violates row-level security policy', code: '42501');
      }, baseDelay: noDelay),
      throwsA(isA<PostgrestException>()),
    );
    expect(calls, 1);
  });

  test('classifies errors', () {
    expect(isTransientError(TimeoutException('x')), isTrue);
    expect(isTransientError(http.ClientException('connection closed')), isTrue);
    expect(isTransientError(const TransientFailure('x')), isTrue);
    expect(isTransientError(FunctionException(status: 503)), isTrue);
    expect(isTransientError(FunctionException(status: 429)), isTrue);
    expect(isTransientError(FunctionException(status: 403)), isFalse);
    expect(isTransientError(const PostgrestException(message: 'x', code: '42501')), isFalse);
    expect(isTransientError(Exception('File too large')), isFalse);
  });
}
