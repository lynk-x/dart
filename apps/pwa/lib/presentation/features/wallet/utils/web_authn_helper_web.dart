// ignore_for_file: uri_does_not_exist, avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:js' as js;
import 'dart:js_util' as js_util;

class WebAuthnHelper {
  /// Checks if the browser and operating system support WebAuthn biometrics.
  static Future<bool> isSupported() async {
    try {
      final jsObject = js.context['lynkWebAuthn'];
      if (jsObject == null) return false;

      final promise = jsObject.callMethod('isSupported');
      final result = await js_util.promiseToFuture(promise);
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Registers a local biometric credential on the device and returns the credential hex ID.
  static Future<String?> registerLocalCredential(String username) async {
    try {
      final jsObject = js.context['lynkWebAuthn'];
      if (jsObject == null) return null;

      final promise = jsObject.callMethod('registerLocalCredential', [username]);
      final result = await js_util.promiseToFuture(promise);
      return result as String?;
    } catch (_) {
      return null;
    }
  }

  /// Prompts the user for local biometrics to unlock and matches against the stored hex ID.
  static Future<bool> authenticateLocalCredential(String hexId) async {
    try {
      final jsObject = js.context['lynkWebAuthn'];
      if (jsObject == null) return false;

      final promise = jsObject.callMethod('authenticateLocalCredential', [hexId]);
      final result = await js_util.promiseToFuture(promise);
      return result == true;
    } catch (_) {
      return false;
    }
  }
}
