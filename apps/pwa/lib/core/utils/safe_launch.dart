import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Schemes allowed for [safeLaunchUrl]. Everything else (javascript:, data:,
/// file:, custom app schemes, etc.) is rejected — these are the only schemes
/// this app ever has a legitimate reason to open from user/server-supplied
/// strings (system-config links, notification action URLs).
const _allowedSchemes = {'http', 'https', 'mailto', 'tel'};

/// Parses and validates [rawUrl] before launching it, restricting to
/// [_allowedSchemes]. Returns `true` if the URL was launched, `false` if it
/// was invalid, had a disallowed scheme, or the platform failed to launch it.
///
/// Defense in depth: today, action_url/system-config URLs only ever reach
/// this app via SECURITY DEFINER server-side code or system_config values an
/// account admin controls (comms.notifications is is_system_admin()-only for
/// INSERT — see 07_comms/policies/comms_rls.sql), not directly attacker-
/// controlled. But nothing downstream re-validates the scheme before handing
/// it to launchUrl, so a future notification-writing path or a misconfigured
/// system_config value could otherwise launch an arbitrary scheme
/// (javascript:, custom app links, etc.) with no gate at all.
Future<bool> safeLaunchUrl(
  String? rawUrl, {
  LaunchMode mode = LaunchMode.platformDefault,
}) async {
  if (rawUrl == null || rawUrl.trim().isEmpty) return false;

  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null) return false;

  if (!_allowedSchemes.contains(uri.scheme.toLowerCase())) {
    debugPrint('[safeLaunchUrl] Blocked disallowed scheme: ${uri.scheme}');
    return false;
  }

  try {
    return await launchUrl(uri, mode: mode);
  } catch (e) {
    debugPrint('[safeLaunchUrl] Failed to launch $rawUrl: $e');
    return false;
  }
}
