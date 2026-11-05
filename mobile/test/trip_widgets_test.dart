import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rideshare_mobile/features/trips/trips.dart';
import 'package:rideshare_mobile/features/trips/widgets/trip_widgets.dart';

void main() {
  const stops = [
    TripStop(name: 'Colombo Fort', lat: 6.93, lng: 79.84),
    TripStop(name: 'Kadawatha', lat: 7.0, lng: 79.95),
    TripStop(name: 'Kandy', lat: 7.29, lng: 80.63),
  ];

  testWidgets('RouteTimeline shows every stop and pickup/drop tags', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: RouteTimeline(stops: stops, highlightFrom: 1, highlightTo: 2))),
    ));
    expect(find.text('Colombo Fort'), findsOneWidget);
    expect(find.text('Kadawatha'), findsOneWidget);
    expect(find.text('Kandy'), findsOneWidget);
    expect(find.text('Pickup'), findsOneWidget);
    expect(find.text('Drop'), findsOneWidget);
  });

  testWidgets('TripStatusChip shows a readable label', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TripStatusChip(TripStatus.inProgress))));
    expect(find.text('In progress'), findsOneWidget);
  });

  testWidgets('cancel dialog requires a reason', (tester) async {
    String? result = 'untouched';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showCancelTripDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel trip'));
    await tester.pump();
    expect(find.text('Please give a reason'), findsOneWidget);
    await tester.tap(find.text('Vehicle breakdown'));
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel trip'));
    await tester.pumpAndSettle();
    expect(result, 'Vehicle breakdown');
  });
}
