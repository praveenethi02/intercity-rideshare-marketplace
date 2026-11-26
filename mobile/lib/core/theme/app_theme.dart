import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// The app's one theme, built from the Figma design system (SCRUM-296).
/// Every screen gets its colours, text styles and component shapes from here.
abstract final class AppTheme {
  static const colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.brand500,
    onPrimary: AppColors.neutral0,
    primaryContainer: AppColors.brand100,
    onPrimaryContainer: AppColors.brand900,
    secondary: AppColors.brand700,
    onSecondary: AppColors.neutral0,
    secondaryContainer: AppColors.brand50,
    onSecondaryContainer: AppColors.brand900,
    tertiary: AppColors.success600,
    onTertiary: AppColors.neutral0,
    tertiaryContainer: AppColors.success100,
    onTertiaryContainer: AppColors.success600,
    error: AppColors.danger500,
    onError: AppColors.neutral0,
    errorContainer: AppColors.danger100,
    onErrorContainer: AppColors.danger700,
    surface: AppColors.neutral0,
    onSurface: AppColors.neutral900,
    onSurfaceVariant: AppColors.neutral600,
    surfaceContainerLowest: AppColors.neutral0,
    surfaceContainerLow: AppColors.neutral50,
    surfaceContainer: AppColors.neutral100,
    surfaceContainerHigh: AppColors.neutral100,
    surfaceContainerHighest: AppColors.neutral200,
    outline: AppColors.neutral400,
    outlineVariant: AppColors.neutral200,
    inverseSurface: AppColors.neutral900,
    onInverseSurface: AppColors.neutral0,
    inversePrimary: AppColors.brand100,
    shadow: Color(0x1A0F172C),
    scrim: Color(0x660F172C),
  );

  /// Inter, bundled in assets/fonts (weights 400, 500, 600 and 700).
  static const fontFamily = 'Inter';

  static ThemeData get light {
    final base = ThemeData(colorScheme: colorScheme, useMaterial3: true, fontFamily: fontFamily);
    // ThemeData.textTheme has no font sizes until Theme applies them, so merge the Material 3
    // size scale in first. Otherwise styles built from it here (app bar title, navigation labels)
    // fall back to 14 px.
    final text = Typography.englishLike2021
        .merge(base.textTheme)
        .apply(fontFamily: fontFamily, bodyColor: AppColors.neutral900, displayColor: AppColors.brand900);
    final textTheme = text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));
    const buttonSize = Size(64, 48);
    const buttonPadding = EdgeInsets.symmetric(horizontal: AppSpacing.xl);

    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.neutral50,
      extensions: const [AppStatusColors.light],
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.neutral50,
        foregroundColor: AppColors.neutral900,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: AppColors.brand900),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.neutral0,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
        border: border(AppColors.neutral200),
        enabledBorder: border(AppColors.neutral200),
        focusedBorder: border(AppColors.brand500, 2),
        errorBorder: border(AppColors.danger500),
        focusedErrorBorder: border(AppColors.danger500, 2),
        disabledBorder: border(AppColors.neutral100),
        labelStyle: const TextStyle(color: AppColors.neutral600),
        hintStyle: const TextStyle(color: AppColors.neutral400),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: rounded,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: rounded,
          foregroundColor: AppColors.brand500,
          side: const BorderSide(color: AppColors.neutral200),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.brand500, textStyle: textTheme.labelLarge),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.brand500,
        foregroundColor: AppColors.neutral0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.neutral0,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.neutral200),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.neutral0,
        selectedColor: AppColors.brand100,
        side: const BorderSide(color: AppColors.neutral200),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        labelStyle: textTheme.labelLarge?.copyWith(color: AppColors.neutral900),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.neutral0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.brand100,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected) ? AppColors.brand500 : AppColors.neutral600,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? AppColors.brand700 : AppColors.neutral600,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(iconColor: AppColors.brand500),
      dividerTheme: const DividerThemeData(color: AppColors.neutral200, space: 1, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.neutral900,
        shape: rounded,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.neutral0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.neutral0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      ),
    );
  }
}
