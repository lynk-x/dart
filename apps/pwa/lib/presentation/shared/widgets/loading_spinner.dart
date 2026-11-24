import 'package:material_ui/material_ui.dart';
import 'package:lynk_core/core.dart';

/// Shared, consistently-branded loading spinner used across the app so every
/// screen doesn't hand-roll its own CircularProgressIndicator with different
/// colors, sizes, and stroke widths.
class LynkLoadingSpinner extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const LynkLoadingSpinner({
    super.key,
    this.size = 40,
    this.color,
    this.strokeWidth = 3,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        color: color ?? context.accentColor,
        strokeWidth: strokeWidth,
      ),
    );
  }
}
