import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rideshare_mobile/core/api_client.dart';
import 'package:rideshare_mobile/core/app_services.dart';
import 'package:rideshare_mobile/core/auth_service.dart';
import 'package:rideshare_mobile/features/home/home_screen.dart';
import 'package:rideshare_mobile/features/trips/data/towns.dart';
import 'package:rideshare_mobile/features/trips/trips.dart';

const _passenger = AppUser(
  id: 'u1',
  firstName: 'Nimal',
  lastName: 'Silva',
  fullName: 'Nimal Silva',
  phone: '+94771234567',
  role: 'PASSENGER',
);

Future<List<String>> _pump(
  WidgetTester tester,
  AppUser user, {
  bool driver = false,
  Widget Function(Widget child)? wrap,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = <String>[];
  await tester.pumpWidget(MaterialApp(
    builder: wrap == null ? null : (context, child) => wrap(child!),
    home: HomeScreen(
      user: user,
      clock: () => DateTime(2026, 11, 17, 9),
      onFindRide: () => opened.add('search'),
      onOpenDriver: () => opened.add('driver'),
      onOpenMyTrips: driver ? () => opened.add('my trips') : null,
      onOpenAccount: () => opened.add('account'),
    ),
  ));
  return opened;
}

void main() {
  test('greetingFor follows the time of day', () {
    expect(greetingFor(DateTime(2026, 1, 1, 8)), 'Good morning');
    expect(greetingFor(DateTime(2026, 1, 1, 13)), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 1, 1, 20)), 'Good evening');
  });

  test('every popular route uses a known town', () {
    final names = kTowns.map((t) => t.name).toSet();
    for (final (from, to) in popularRoutes) {
      expect(names, containsAll([from, to]));
    }
  });

  test('greetingName falls back to the first word of the full name', () {
    const old = AppUser(id: 'u', fullName: 'Kasun Perera', phone: '', role: 'PASSENGER');
    expect(old.greetingName, 'Kasun');
    expect(_passenger.greetingName, 'Nimal');
  });

  testWidgets('greets the user by first name', (tester) async {
    await _pump(tester, _passenger);
    expect(find.text('Good morning, Nimal'), findsOneWidget);
  });

  testWidgets('the avatar shows the initials and opens Account', (tester) async {
    final opened = await _pump(tester, _passenger);
    await tester.tap(find.text('NS'));
    expect(opened, ['account']);
  });

  testWidgets('the search card opens Find a ride', (tester) async {
    final opened = await _pump(tester, _passenger);
    await tester.tap(find.text('Where to?'));
    expect(opened, ['search']);
  });

  testWidgets('a passenger is invited to become a driver', (tester) async {
    final opened = await _pump(tester, _passenger);
    expect(find.text('Earn from your empty seats'), findsOneWidget);
    expect(find.text('My trips'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Become a driver'));
    expect(opened, ['driver']);
  });

  testWidgets('a driver gets a shortcut to My trips instead', (tester) async {
    final opened = await _pump(tester, _passenger.copyWith(role: 'DRIVER'), driver: true);
    expect(find.text('Earn from your empty seats'), findsNothing);

    await tester.tap(find.text('My trips'));
    expect(opened, ['my trips']);
  });

  testWidgets('a popular route searches that route for tomorrow', (tester) async {
    Uri? searched;
    final trips = TripRepository(ApiClient(
      baseUrl: 'http://test/api/v1',
      tokenProvider: () async => 't',
      httpClient: MockClient((request) async {
        searched = request.url;
        return http.Response(jsonEncode({'success': true, 'message': 'OK', 'data': [], 'meta': null}), 200);
      }),
    ));
    await _pump(tester, _passenger, wrap: (child) => AppServices(trips: trips, child: child));

    await tester.tap(find.text('Galle'));
    await tester.pumpAndSettle();

    final galle = kTowns.firstWhere((t) => t.name == 'Galle');
    expect(searched?.path, '/api/v1/trips/search');
    expect(searched?.queryParameters, containsPair('date', '2026-11-18'));
    expect(searched?.queryParameters, containsPair('toLat', '${galle.lat}'));
  });
}
