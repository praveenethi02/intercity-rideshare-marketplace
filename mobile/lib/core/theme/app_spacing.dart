import 'package:flutter/widgets.dart';

/// Spacing steps from the Figma design system (a 4-point grid). Use these instead of
/// writing numbers in padding and SizedBox.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Padding around the content of a screen.
  static const screen = EdgeInsets.all(lg);
}

/// Corner radius steps.
abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const pill = 999.0;
}
