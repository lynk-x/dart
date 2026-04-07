import 'package:flutter/material.dart';

/// Shared screen-size breakpoints for PWA/responsive adaptation.
///
/// Usage:
/// ```dart
/// if (Breakpoints.isTablet(context)) {
///   // Use two-column layout
/// }
///
/// ConstrainedBox(
///   constraints: const BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
///   child: myWidget,
/// )
/// ```
///
/// Breakpoints follow the Material Design adaptive layout guidance:
/// - Phone   : < 600px
/// - Tablet  : 600px – 1023px
/// - Desktop : >= 1024px
class Breakpoints {
  Breakpoints._();

  /// Tablet breakpoint (600dp). Content starts to benefit from wider layouts.
  static const double tablet = 600;

  /// Desktop breakpoint (1024dp). Multi-column layouts are appropriate.
  static const double desktop = 1024;

  /// Maximum single-column content width.
  /// Prevents text/cards from stretching uncomfortably on wide screens.
  static const double maxContentWidth = 680;

  /// Maximum card width — used for ticket, detail cards, etc.
  static const double maxCardWidth = 500;

  /// Returns true when the screen width is >= [tablet].
  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= tablet;

  /// Returns true when the screen width is >= [desktop].
  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= desktop;

  /// Returns the number of grid columns appropriate for the current width.
  ///
  /// Used for category pickers, media grids, etc.
  static int gridColumns(BuildContext context, {int phoneColumns = 2, int tabletColumns = 4}) {
    return isTablet(context) ? tabletColumns : phoneColumns;
  }

  /// Wraps [child] in a horizontally-centered, max-width-constrained box.
  ///
  /// Convenient shorthand for page body content that should not stretch
  /// beyond [maxWidth] on large screens.
  static Widget constrain(Widget child, {double maxWidth = maxContentWidth}) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
