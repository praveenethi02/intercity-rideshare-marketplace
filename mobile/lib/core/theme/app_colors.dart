import 'package:flutter/material.dart';

/// Colours from the Figma design system. They match the CSS variables in admin/src/shell.css,
/// so the mobile app and the admin dashboard look like one product.
///
/// Screens should read colours from `Theme.of(context).colorScheme` or [AppStatusColors].
/// Use these constants only inside the theme.
abstract final class AppColors {
  static const brand900 = Color(0xFF0B203F);
  static const brand700 = Color(0xFF153A88);
  static const brand500 = Color(0xFF1257D9);
  static const brand100 = Color(0xFFD8E3FF);
  static const brand50 = Color(0xFFECF3FF);

  static const success600 = Color(0xFF119363);
  static const success100 = Color(0xFFE4F5EB);
  static const warn500 = Color(0xFFE08C00);
  static const warn700 = Color(0xFF9A6100);
  static const warn100 = Color(0xFFFFF2D9);
  static const danger500 = Color(0xFFD82E3B);
  static const danger700 = Color(0xFFB81F2C);
  static const danger100 = Color(0xFFFFE8E8);

  static const neutral0 = Color(0xFFFFFFFF);
  static const neutral50 = Color(0xFFF5F6FA);
  static const neutral100 = Color(0xFFF0F1F5);
  static const neutral200 = Color(0xFFDCE3EB);
  static const neutral400 = Color(0xFF9AA7B7);
  static const neutral600 = Color(0xFF5A6778);
  static const neutral900 = Color(0xFF0F172C);
}

/// The kinds of status a badge can show. Each feature maps its own statuses to one of these.
enum StatusTone { info, success, warning, danger, neutral }

/// Foreground and background colours for each [StatusTone], read from the theme.
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  final Map<StatusTone, ({Color foreground, Color background})> tones;

  const AppStatusColors(this.tones);

  static const light = AppStatusColors({
    StatusTone.info: (foreground: AppColors.brand700, background: AppColors.brand50),
    StatusTone.success: (foreground: AppColors.success600, background: AppColors.success100),
    StatusTone.warning: (foreground: AppColors.warn700, background: AppColors.warn100),
    StatusTone.danger: (foreground: AppColors.danger700, background: AppColors.danger100),
    StatusTone.neutral: (foreground: AppColors.neutral600, background: AppColors.neutral100),
  });

  /// The colours for [tone]. Falls back to [light] when the theme has no extension, as in tests.
  static ({Color foreground, Color background}) of(BuildContext context, StatusTone tone) =>
      (Theme.of(context).extension<AppStatusColors>() ?? light).tones[tone]!;

  @override
  AppStatusColors copyWith({Map<StatusTone, ({Color foreground, Color background})>? tones}) =>
      AppStatusColors(tones ?? this.tones);

  @override
  AppStatusColors lerp(AppStatusColors? other, double t) => t < 0.5 || other == null ? this : other;
}
