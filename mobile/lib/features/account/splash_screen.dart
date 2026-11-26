import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/common_widgets.dart';

/// Shown while the app signs the user back in from a saved session (SCRUM-298).
/// It replaces the plain spinner that was shown before.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // About 60% of the screen width, never larger than 280.
    final logoSize = math.min(MediaQuery.sizeOf(context).width * 0.6, 280.0);
    return Scaffold(
      // The logo has a white background, so the page uses the same white surface.
      backgroundColor: colors.surface,
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(children: [
            const Spacer(flex: 3),
            AppLogo(size: logoSize),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Book your seat, bid fairly, travel safely.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const Spacer(flex: 2),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3, color: colors.primary),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ]),
        ),
      ),
    );
  }
}
