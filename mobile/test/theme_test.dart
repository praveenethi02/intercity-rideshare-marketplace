import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rideshare_mobile/core/theme/app_colors.dart';
import 'package:rideshare_mobile/core/theme/app_theme.dart';
import 'package:rideshare_mobile/core/widgets/common_widgets.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: child)));

void main() {
  group('AppTheme', () {
    test('uses the Figma brand colours', () {
      final theme = AppTheme.light;
      expect(theme.colorScheme.primary, AppColors.brand500);
      expect(theme.colorScheme.error, AppColors.danger500);
      expect(theme.scaffoldBackgroundColor, AppColors.neutral50);
      expect(theme.useMaterial3, isTrue);
    });

    test('has a colour for every status tone', () {
      final status = AppTheme.light.extension<AppStatusColors>()!;
      for (final tone in StatusTone.values) {
        expect(status.tones[tone], isNotNull, reason: '$tone');
      }
    });

    test('component text styles have real font sizes', () {
      final theme = AppTheme.light;
      expect(theme.appBarTheme.titleTextStyle?.fontSize, 22);
      final label = theme.navigationBarTheme.labelTextStyle!.resolve({WidgetState.selected});
      expect(label?.fontSize, 12);
    });

    test('every text style uses the bundled Inter font at the Material 3 sizes', () {
      final text = AppTheme.light.textTheme;
      const m3 = Typography.englishLike2021;
      final pairs = {
        'displayLarge': (text.displayLarge, m3.displayLarge),
        'headlineSmall': (text.headlineSmall, m3.headlineSmall),
        'titleLarge': (text.titleLarge, m3.titleLarge),
        'titleMedium': (text.titleMedium, m3.titleMedium),
        'bodyLarge': (text.bodyLarge, m3.bodyLarge),
        'bodyMedium': (text.bodyMedium, m3.bodyMedium),
        'labelLarge': (text.labelLarge, m3.labelLarge),
        'labelSmall': (text.labelSmall, m3.labelSmall),
      };
      for (final MapEntry(key: name, value: (style, size)) in pairs.entries) {
        expect(style?.fontFamily, AppTheme.fontFamily, reason: name);
        expect(style?.fontSize, size?.fontSize, reason: name);
      }
      expect(AppTheme.light.appBarTheme.titleTextStyle?.fontFamily, AppTheme.fontFamily);
    });

    test('buttons are at least 48 pixels tall for easy tapping', () {
      final style = AppTheme.light.filledButtonTheme.style!;
      expect(style.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(48));
    });
  });

  group('AppBadge', () {
    testWidgets('shows the label in the tone colour', (tester) async {
      await _pump(tester, const AppBadge('Approved', tone: StatusTone.success));

      final text = tester.widget<Text>(find.text('Approved'));
      expect(text.style?.color, AppStatusColors.light.tones[StatusTone.success]!.foreground);
    });

    testWidgets('works without the theme extension', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AppBadge('Draft')));
      expect(find.text('Draft'), findsOneWidget);
    });
  });

  testWidgets('EmptyView shows its message and action', (tester) async {
    await _pump(
      tester,
      EmptyView(
          icon: Icons.directions_car,
          message: 'No trips yet',
          action: TextButton(onPressed: () {}, child: const Text('New trip'))),
    );
    expect(find.text('No trips yet'), findsOneWidget);
    expect(find.text('New trip'), findsOneWidget);
  });

  testWidgets('ErrorView shows the error and a retry button', (tester) async {
    var retried = false;
    await _pump(tester, ErrorView(error: 'Cannot reach the server', onRetry: () => retried = true));

    expect(find.text('Cannot reach the server'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('SkeletonList is announced as loading', (tester) async {
    await _pump(tester, const SkeletonList());
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}
