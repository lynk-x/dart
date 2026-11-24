import 'package:material_ui/material_ui.dart';
import 'package:lynk_core/core.dart';

/// Shared, consistently-styled snackbar helpers (success/error/info) so
/// feedback across the app doesn't each hand-roll its own SnackBar.
class AppSnackBars {
  static void showSuccess(BuildContext context, String message) {
    _show(context, message, Icons.check_circle_outline, context.accentColor);
  }

  static void showError(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(context, message, Icons.error_outline, Colors.redAccent,
        actionLabel: actionLabel, onAction: onAction);
  }

  static void showInfo(BuildContext context, String message) {
    _show(context, message, Icons.info_outline, Colors.blueAccent);
  }

  /// Text-only snackbar for informational messages that don't fit the
  /// standard success/error/info templates (e.g. mode toggles, feedback
  /// confirmations, emoji-rich notices). No action button — purely
  /// informational.
  static void showNeutral(
    BuildContext context, {
    required Widget content,
    Color? backgroundColor,
    SnackBarBehavior? behavior,
    Duration? duration,
    ShapeBorder? shape,
    EdgeInsetsGeometry? margin,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: content,
        backgroundColor: backgroundColor ?? const Color(0xFF1A1A1A),
        behavior: behavior ?? SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 4),
        shape: shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: margin ?? const EdgeInsets.all(16),
      ),
    );
  }

  /// Snackbar with a required action button (e.g. Undo, Retry, Dismiss).
  /// Use when the user needs to take immediate action on the message.
  static void showAction(
    BuildContext context, {
    required Widget content,
    required SnackBarAction action,
    Color? backgroundColor,
    SnackBarBehavior? behavior,
    Duration? duration,
    ShapeBorder? shape,
    EdgeInsetsGeometry? margin,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: content,
        backgroundColor: backgroundColor ?? const Color(0xFF1A1A1A),
        behavior: behavior ?? SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 8),
        action: action,
        shape: shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: margin ?? const EdgeInsets.all(16),
      ),
    );
  }

  static void _show(
    BuildContext context,
    String message,
    IconData icon,
    Color color, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppTypography.inter(fontSize: 13, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: onAction != null ? 8 : 4),
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(label: actionLabel, textColor: color, onPressed: onAction)
            : null,
      ),
    );
  }
}
