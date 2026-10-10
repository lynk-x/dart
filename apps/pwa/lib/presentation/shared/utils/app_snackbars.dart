import 'package:flutter/material.dart';
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
