import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// Shown while the app signs the user back in from a saved session (SCRUM-298).
/// It replaces the plain spinner that was shown before.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final onPrimary = colors.onPrimary;
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.primary, colors.onPrimaryContainer],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            const Spacer(flex: 3),
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: onPrimary,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Icon(Icons.navigation, size: 48, color: colors.primary, semanticLabel: 'Intercity Rideshare'),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Intercity Rideshare',
              style: theme.textTheme.headlineSmall?.copyWith(color: onPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Book your seat, bid fairly, travel safely.',
              style: theme.textTheme.bodyMedium?.copyWith(color: onPrimary.withValues(alpha: 0.85)),
            ),
            const Spacer(flex: 2),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3, color: onPrimary),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ]),
        ),
      ),
    );
  }
}
