import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rideshare_mobile/core/api_client.dart';
import 'package:rideshare_mobile/core/app_services.dart';
import 'package:rideshare_mobile/core/theme/app_theme.dart';
import 'package:rideshare_mobile/features/bookings/bookings.dart';
import 'package:rideshare_mobile/features/trips/trips.dart';

http.Response _ok(Object? data, [int status = 200]) =>
    http.Response(jsonEncode({'success': true, 'message': 'OK', 'data': data, 'meta': null}), status);

http.Response _fail(int status, String code, String message) => http.Response(
      jsonEncode({'success': false, 'message': message, 'data': null, 'meta': {'code': code}}),
      status,
    );

const _trip = {
  'id': 't1',
  'driverId': 'd1',
  'vehicleId': 'v1',
  'pricingMode': 'FIXED',
  'status': 'SCHEDULED',
  'departureAt': '2026-11-25T01:30:00.000Z',
  'seatsOffered': 4,
  'basePriceCents': 300000,
  'distanceKm': 115,
  'stops': [
    {'order': 0, 'name': 'Colombo Fort', 'lat': 6.93, 'lng': 79.84},
    {'order': 1, 'name': 'Kadawatha', 'lat': 7.0, 'lng': 79.95},
    {'order': 2, 'name': 'Kandy', 'lat': 7.29, 'lng': 80.63},
  ],
};

Map<String, dynamic> _booking({String id = 'b1', String status = 'CONFIRMED', String tripStatus = 'SCHEDULED'}) => {
      'id': id,
      'reference': 'BK-7Q2K9M',
      'status': status,
      'tripId': 't1',
      'passengerId': 'p1',
      'fromStop': 1,
      'toStop': 2,
      'seats': 2,
      'pricePerSeatCents': 220000,
      'totalCents': 440000,
      'cancelReason': null,
      'createdAt': '2026-11-20T08:30:00.000Z',
      'cancelledAt': null,
      'pickup': {'stopOrder': 1, 'name': 'Kadawatha', 'plannedAt': null},
      'drop': {'stopOrder': 2, 'name': 'Kandy', 'plannedAt': null},
      'trip': {
        'id': 't1',
        'driverId': 'd1',
        'pricingMode': 'FIXED',
        'status': tripStatus,
        'originName': 'Colombo Fort',
        'destinationName': 'Kandy',
        'departureAt': '2026-11-25T01:30:00.000Z',
        'estimatedArrivalAt': null,
      },
    };

const _selection = SegmentSelection(
  tripId: 't1',
  fromStop: 1,
  toStop: 2,
  seats: 2,
  pricingMode: 'FIXED',
  pricePerSeatCents: 220000,
);

/// A fake backend that records what the app sent.
class _Server {
  final Map<String, Object?> sent = {};
  http.Response Function(http.Request request)? onCreate;
  List<Map<String, dynamic>> upcoming = [_booking()];

  http.Client get client => MockClient((request) async {
        final path = request.url.path.replaceFirst('/api/v1', '');
        if (path == '/trips/t1') return _ok({'trip': _trip});
        if (request.method == 'POST' && path == '/bookings') {
          sent['create'] = jsonDecode(request.body);
          return onCreate?.call(request) ?? _ok({'booking': _booking()}, 201);
        }
        if (path == '/bookings/mine') {
          final when = request.url.queryParameters['when'];
          return _ok({'bookings': when == 'upcoming' ? upcoming : <Object>[]});
        }
        if (request.method == 'POST' && path == '/bookings/b1/cancel') {
          sent['cancel'] = true;
          upcoming = [];
          return _ok({'booking': _booking(status: 'CANCELLED')});
        }
        return _fail(404, 'NOT_FOUND', 'Not found');
      });

  ApiClient get api => ApiClient(baseUrl: 'http://test/api/v1', tokenProvider: () async => 't', httpClient: client);
}

Future<void> _pump(WidgetTester tester, _Server server, Widget Function(BookingApi api) screen) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = server.api;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => AppServices(trips: TripRepository(api), child: child!),
    home: screen(BookingApi(api)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('Booking.fromJson reads the API booking object', () {
    final b = Booking.fromJson(_booking());
    expect(b.reference, 'BK-7Q2K9M');
    expect(b.pickup.name, 'Kadawatha');
    expect(b.drop.name, 'Kandy');
    expect(b.totalCents, 440000);
    expect(b.canCancel, isTrue);
    expect(Booking.fromJson(_booking(tripStatus: 'IN_PROGRESS')).canCancel, isFalse);
    expect(Booking.fromJson(_booking(status: 'CANCELLED')).canCancel, isFalse);
  });

  group('ConfirmBookingScreen', () {
    testWidgets('shows the route, seats and total', (tester) async {
      await _pump(tester, _Server(), (api) => ConfirmBookingScreen(api: api, selection: _selection));

      expect(find.text('Kadawatha'), findsOneWidget);
      expect(find.text('Kandy'), findsOneWidget);
      expect(find.text('LKR 2,200'), findsOneWidget);
      expect(find.text('LKR 4,400'), findsOneWidget);
    });

    testWidgets('confirming books without sending a price and shows the reference', (tester) async {
      final server = _Server();
      await _pump(tester, server, (api) => ConfirmBookingScreen(api: api, selection: _selection));

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      expect(server.sent['create'], {'tripId': 't1', 'fromStop': 1, 'toStop': 2, 'seats': 2});
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(find.text('BK-7Q2K9M'), findsOneWidget);
    });

    testWidgets('shows the server error and stays on the screen', (tester) async {
      final server = _Server()
        ..onCreate = (_) => _fail(409, 'NOT_ENOUGH_SEATS', 'Not enough seats on this part of the route');
      await _pump(tester, server, (api) => ConfirmBookingScreen(api: api, selection: _selection));

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      expect(find.text('Not enough seats on this part of the route'), findsOneWidget);
      expect(find.text('Booking confirmed'), findsNothing);
    });
  });

  group('MyBookingsScreen', () {
    testWidgets('lists upcoming bookings and an empty past tab', (tester) async {
      await _pump(tester, _Server(), (api) => MyBookingsScreen(api: api));

      expect(find.text('BK-7Q2K9M'), findsOneWidget);
      expect(find.text('Kadawatha → Kandy'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();
      expect(find.text('No past bookings yet.'), findsOneWidget);
    });

    testWidgets('cancelling asks first, then removes the booking', (tester) async {
      final server = _Server();
      await _pump(tester, server, (api) => MyBookingsScreen(api: api));

      await tester.tap(find.text('Cancel booking'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel booking BK-7Q2K9M?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
      await tester.pumpAndSettle();

      expect(server.sent['cancel'], isTrue);
      expect(find.text('Booking cancelled'), findsOneWidget);
      expect(find.text('BK-7Q2K9M'), findsNothing);
    });
  });
}