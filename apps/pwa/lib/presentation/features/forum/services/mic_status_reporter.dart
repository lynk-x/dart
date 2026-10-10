// Reports how the call microphone was set up (RNNoise vs browser noise suppression) so fallback
// rates are visible without logging anything per call: every call just gets a Sentry tag that
// rides along on any error from that session, and only fallbacks — rare and actionable — are
// sent as their own events.
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:web/web.dart' as web;

@JS('window.lynkMicProcessor.getLastStatus')
external JSString _jsGetLastMicStatus();

bool _listeningForChanges = false;

/// The mic can change mode mid-call (the CPU watchdog in web/js/mic_watchdog.js bypasses RNNoise on
/// an overloaded device and fires 'lynk-mic-status'); report that as it happens rather than only
/// at call start. Idempotent.
void _listenForMicStatusChanges() {
  if (_listeningForChanges) return;
  _listeningForChanges = true;
  web.window.addEventListener('lynk-mic-status', ((web.Event _) => reportMicStatus()).toJS);
}

/// Reads the status of the most recent mic setup from web/js/mic_processor.js and forwards it.
/// Call right after a successful startLocalMicrophone / startVideoStream; also runs by itself when
/// the mic changes mode mid-call. Never throws.
void reportMicStatus() {
  if (!kIsWeb) return;
  _listenForMicStatusChanges();
  try {
    final status = jsonDecode(_jsGetLastMicStatus().toDart) as Map<String, dynamic>;
    final mode = status['mode'] as String? ?? 'none';
    if (mode == 'none') return;
    final reason = status['reason'] as String?;
    final setupMs = status['setupMs'] as int?;
    final degradedAfterMs = status['degradedAfterMs'] as int?;

    Sentry.configureScope((scope) {
      scope.setTag('mic_mode', mode);
      if (setupMs != null) {
        scope.setContexts('mic_processing', {
          'setup_ms': setupMs,
          'reason': reason,
          if (degradedAfterMs != null) 'degraded_after_ms': degradedAfterMs,
        });
      }
    });
    Sentry.addBreadcrumb(Breadcrumb(
      category: 'call.mic',
      message: 'mic mode: $mode${reason != null ? ' ($reason)' : ''}',
      data: {if (setupMs != null) 'setup_ms': setupMs},
    ));

    if (mode == 'browser_fallback') {
      Sentry.captureMessage(
        'RNNoise unavailable, using browser noise suppression',
        level: SentryLevel.info,
        withScope: (scope) => scope.setTag('mic_fallback_reason', _bucketReason(reason)),
      );
    }
  } catch (e) {
    debugPrint('[MicStatusReporter] failed: $e');
  }
}

// Low-cardinality tag value so Sentry can group fallbacks; the full reason is in the context.
String _bucketReason(String? reason) {
  final r = (reason ?? '').toLowerCase();
  if (r.contains('cpu_overload')) return 'cpu_overload';
  if (r.contains('timeout')) return 'timeout';
  if (r.contains('samplerate')) return 'sample_rate';
  if (r.contains('worklet') || r.contains('addmodule')) return 'worklet_load';
  if (r.contains('wasm') || r.contains('http')) return 'asset_fetch';
  return 'other';
}
