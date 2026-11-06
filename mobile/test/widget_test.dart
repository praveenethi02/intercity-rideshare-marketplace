// Smoke test. Also stops `flutter create .` from adding its default counter test.
import 'package:flutter_test/flutter_test.dart';
import 'package:rideshare_mobile/core/session_store.dart';
import 'package:rideshare_mobile/main.dart';

void main() {
  testWidgets('app starts on the sign-in screen', (tester) async {
    await tester.pumpWidget(RideshareApp(store: MemorySessionStore()));
    await tester.pumpAndSettle();
    expect(find.text('Mobile number'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('sign-in has no manual vehicle settings', (tester) async {
    await tester.pumpWidget(RideshareApp(store: MemorySessionStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Developer settings'));
    await tester.pumpAndSettle();
    expect(find.text('API base URL'), findsOneWidget);
    expect(find.textContaining('Vehicle ID'), findsNothing);
    expect(find.textContaining('Vehicle seats'), findsNothing);
    expect(find.text('00000000-0000-4000-8000-000000000001'), findsNothing);
  });
}
