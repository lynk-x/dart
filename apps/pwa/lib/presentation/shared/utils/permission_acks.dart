import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/permission_request_sheet.dart';

/// Every app-level permission "acknowledgment" the PWA gates behind a
/// one-time explainer sheet before requesting the underlying capability.
///
/// On Flutter Web/PWA, [camera] is the only one with a real, checkable
/// OS/browser permission state — the rest ([media], which backs image/file
/// pickers, [vibration], and [biometric]) have no OS permission API at all
/// on web; the sheet there is purely an app-level courtesy explanation, not
/// a gate on an actual system permission. Push notification permission is
/// tracked separately via PushNotificationService.checkPermissionStatus(),
/// since Firebase already exposes real, live status there — it doesn't need
/// (and shouldn't duplicate) an ack flag of its own.
enum PermissionAckType { camera, media, vibration, biometric }

/// Centralizes the "check ack flag → show [PermissionRequestSheet] if
/// unacknowledged → persist the flag on grant" pattern that was previously
/// copy-pasted (with three different key-naming conventions:
/// camera_permission_acknowledged, vibration_permission_acknowledged,
/// media_permission_acknowledged) across the wallet, ticket scanner, and
/// forum media features.
class PermissionAcks {
  PermissionAcks._();

  static String _key(PermissionAckType type) => 'permission_ack_${type.name}';

  static Future<bool> isAcknowledged(PermissionAckType type) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(type)) ?? false;
  }

  static Future<void> setAcknowledged(PermissionAckType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(type), true);
  }

  /// Runs [onReady] immediately if [type] is already acknowledged; otherwise
  /// shows the shared explainer sheet first, persists the acknowledgment on
  /// "Continue", then runs [onReady]. [onDenied] fires if the user dismisses
  /// via "Not now" instead.
  static Future<void> ensureAcknowledged(
    BuildContext context,
    PermissionAckType type, {
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onReady,
    VoidCallback? onDenied,
    String actionLabel = 'Continue',
    bool isDismissible = true,
    bool enableDrag = true,
  }) async {
    final alreadyAcknowledged = await isAcknowledged(type);
    if (alreadyAcknowledged) {
      onReady();
      return;
    }
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      builder: (sheetContext) => PermissionRequestSheet(
        title: title,
        description: description,
        icon: icon,
        actionLabel: actionLabel,
        onGranted: () async {
          await setAcknowledged(type);
          onReady();
        },
        onDenied: onDenied,
      ),
    );
  }
}
