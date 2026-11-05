// Smoke test. Also stops `flutter create .` from adding its default counter test.
import 'package:flutter_test/flutter_test.dart';
import 'package:rideshare_mobile/main.dart';

void main() {
  testWidgets('app starts on the sign-in screen', (tester) async {
    await tester.pumpWidget(const RideshareApp());
    expect(find.text('Mobile number'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
