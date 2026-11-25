import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rideshare_mobile/core/api_client.dart';
import 'package:rideshare_mobile/core/app_services.dart';
import 'package:rideshare_mobile/core/theme/app_theme.dart';
import 'package:rideshare_mobile/features/trips/trips.dart';
import 'package:rideshare_mobile/features/trips/widgets/driver_vehicle_card.dart';

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'success': true, 'message': 'OK', 'data': data, 'meta': null}), 200);

http.Response _fail(int status, String code, String message) => http.Response(
      jsonEncode({
        'success': false,
        'message': message,
        'data': null,
        'meta': {'code': code}
      }),
      status,
    );

const _vehicle = {'type': 'THREE_WHEELER', 'make': 'Bajaj', 'model': 'RE', 'year': 2019, 'color': 'Green'};

/// GET /trips/t1. Without [vehicle] the field is left out, as older servers do.
Map<String, dynamic> _trip({Map<String, dynamic>? vehicle = _vehicle}) => {
      'id': 't1',
      'driverId': 'd1',
      'vehicleId': 'v1',
      'pricingMode': 'FIXED',
      'status': 'SCHEDULED',
      'departureAt': '2026-11-27T00:30:00.000Z',
      'seatsOffered': 3,
      'basePriceCents': 250000,
      'distanceKm': 115,
      'stops': [
        {'order': 0, 'name': 'Colombo Fort', 'lat': 6.93, 'lng': 79.84, 'distanceFromStartKm': 0},
        {'order': 1, 'name': 'Kandy', 'lat': 7.29, 'lng': 80.63, 'distanceFromStartKm': 115},
      ],
      if (vehicle != null) 'vehicle': vehicle,
    };

Map<String, dynamic> _driver({
  String name = 'Nimal S.',
  double rating = 4.66,
  int count = 12,
  bool verified = true,
  String? photoUrl,
}) =>
    {
      'id': 'd1',
      'fullName': name,
      'photoUrl': photoUrl,
      'averageRating': rating,
      'ratingCount': count,
      'completedTrips': 31,
      'verifiedDriver': verified,
      'memberSince': '2026-11-01',
    };

class _Server {
  Map<String, dynamic> trip = _trip();
  Map<String, dynamic> driver = _driver();
  bool driverFails = false;
  int driverCalls = 0;

  ApiClient get api => ApiClient(
        baseUrl: 'http://test/api/v1',
        tokenProvider: () async => 't',
        httpClient: MockClient((request) async {
          final path = request.url.path.replaceFirst('/api/v1', '');
          if (path == '/trips/t1') return _ok({'trip': trip});
          if (path == '/trips/t1/availability') {
            return _ok({
              'availability': {
                'tripId': 't1',
                'fromStop': 0,
                'toStop': 1,
                'seatsAvailable': 3,
                'segmentPriceCents': 250000,
              },
            });
          }
          if (path == '/drivers/d1') {
            driverCalls++;
            return driverFails ? _fail(500, 'INTERNAL_ERROR', 'Server down') : _ok({'driver': driver});
          }
          return _fail(404, 'NOT_FOUND', 'Not found');
        }),
      );
}

Future<void> _pump(
  WidgetTester tester,
  _Server server, {
  BookSegmentCallback? onBook,
  Size size = const Size(800, 2400),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: AppServices(trips: TripRepository(server.api), onBookSegment: onBook, child: child!),
    ),
    home: const PassengerTripDetailScreen(tripId: 't1', fromStop: 0, toStop: 1),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('models', () {
    test('vehicle types have readable labels, also unknown ones', () {
      String label(String type) => TripVehicle.fromJson({..._vehicle, 'type': type}).typeLabel;
      expect(label('THREE_WHEELER'), 'Three-wheeler');
      expect(label('SUV'), 'SUV');
      expect(label('MINIBUS'), 'Mini bus');
      expect(label('ELECTRIC_BIKE'), 'Electric bike');
    });

    test('a trip without the vehicle field still parses', () {
      expect(Trip.fromJson(_trip(vehicle: null)).vehicle, isNull);
      expect(Trip.fromJson({..._trip(), 'vehicle': null}).vehicle, isNull);
      expect(Trip.fromJson(_trip()).vehicle!.plateNumber, isNull);
    });

    test('a driver profile needs only its id', () {
      final driver = DriverPublicProfile.fromJson({'id': 'd1'});
      expect(driver.ratingLabel, 'No ratings yet');
      expect(driver.verified, isFalse);
    });
  });

  testWidgets('shows the driver and the vehicle, without a plate number', (tester) async {
    await _pump(tester, _Server());

    expect(find.text('Driver and vehicle'), findsOneWidget);
    expect(find.text('Nimal S.'), findsOneWidget);
    expect(find.text('Verified driver'), findsOneWidget);
    expect(find.text('4.7 (12)'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('Three-wheeler'), findsOneWidget);
    expect(find.text('Bajaj RE'), findsOneWidget);
    expect(find.text('2019'), findsOneWidget);
    expect(find.text('Green'), findsOneWidget);
    expect(find.text('Plate number'), findsNothing);
    expect(find.byIcon(Icons.person), findsOneWidget); // no photo
  });

  testWidgets('a driver with no ratings who is not verified', (tester) async {
    await _pump(tester, _Server()..driver = _driver(rating: 0, count: 0, verified: false));

    expect(find.text('No ratings yet'), findsOneWidget);
    expect(find.text('Verified driver'), findsNothing);
  });

  testWidgets('a photo that cannot be loaded shows the fallback icon', (tester) async {
    // Image requests in widget tests always fail with status 400.
    await _pump(tester, _Server()..driver = _driver(photoUrl: 'http://test/broken.png'));

    expect(tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage, isA<NetworkImage>());
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a driver profile error has its own retry, and Book still works', (tester) async {
    final server = _Server()..driverFails = true;
    SegmentSelection? selected;
    await _pump(tester, server, onBook: (context, selection) async => selected = selection);

    expect(find.text('Could not load the driver details.'), findsOneWidget);
    expect(find.text('Three-wheeler'), findsOneWidget);
    expect(find.text('3 of 3 seats left on your part'), findsOneWidget);

    await tester.tap(find.text('Book 1 seat · LKR 2,500'));
    await tester.pumpAndSettle();
    expect(selected?.tripId, 't1');

    server.driverFails = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Nimal S.'), findsOneWidget);
    expect(find.text('Could not load the driver details.'), findsNothing);
  });

  testWidgets('an older server sends no vehicle', (tester) async {
    await _pump(tester, _Server()..trip = _trip(vehicle: null));

    expect(find.text('Not available'), findsOneWidget);
    expect(find.text('Nimal S.'), findsOneWidget);
  });

  testWidgets('scrolling away and back does not load the driver again', (tester) async {
    final server = _Server();
    await _pump(tester, server, size: const Size(400, 500));
    await tester.scrollUntilVisible(find.byType(DriverVehicleCard), 150);
    await tester.pumpAndSettle();
    expect(server.driverCalls, 1);

    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 5000));
    await tester.pump(const Duration(seconds: 1));
    expect(server.driverCalls, 1);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the section fits a 320 px wide screen at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(320, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(size: const Size(320, 1600), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: ListView(children: [
              DriverVehicleCard(
                loadDriver: () async => DriverPublicProfile.fromJson(_driver(name: 'Wickramasinghage S.')),
                vehicle: TripVehicle.fromJson({..._vehicle, 'plateNumber': 'WP CAB-1234'}),
              ),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('WP CAB-1234'), findsOneWidget);
    });
  }

  testWidgets('ride details fit a 320 px wide screen', (tester) async {
    await _pump(tester, _Server(), size: const Size(320, 2400));
    expect(tester.takeException(), isNull);
    expect(find.text('Three-wheeler'), findsOneWidget);
  });

  testWidgets('ride details fit a 320 px wide screen with large text', (tester) async {
    await _pump(tester, _Server(), size: const Size(320, 4800), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Three-wheeler'), findsOneWidget);
  });
}
