class WebAuthnHelper {
  /// Checks if the browser and operating system support WebAuthn biometrics.
  static Future<bool> isSupported() async => false;

  /// Registers a local biometric credential on the device and returns the credential hex ID.
  static Future<String?> registerLocalCredential(String username) async => null;

  /// Prompts the user for local biometrics to unlock and matches against the stored hex ID.
  static Future<bool> authenticateLocalCredential(String hexId) async => false;
}
