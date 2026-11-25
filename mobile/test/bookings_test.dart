import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rideshare_mobile/core/api_client.dart';
import 'package:rideshare_mobile/core/app_services.dart';
import 'package:rideshare_mobile/core/formatters.dart';
import 'package:rideshare_mobile/core/theme/app_theme.dart';
import 'package:rideshare_mobile/core/widgets/common_widgets.dart';
import 'package:rideshare_mobile/features/bookings/bookings.dart';
import 'package:rideshare_mobile/features/trips/trips.dart';
import 'package:rideshare_mobile/features/trips/widgets/trip_widgets.dart';

http.Response _ok(Object? data, [int status = 200]) =>
    http.Response(jsonEncode({'success': true, 'message': 'OK', 'data': data, 'meta': null}), status);

http.Response _fail(int status, String code, String message) => http.Response(
      jsonEncode({
        'success': false,
        'message': message,
        'data': null,
        'meta': {'code': code}
      }),
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

const _plate = 'WP CAB-1234';

/// GET /bookings/b1: the booking with its journey details.
Map<String, dynamic> _details({
  String status = 'CONFIRMED',
  String tripStatus = 'SCHEDULED',
  String? plate = _plate,
  String? cancelReason,
  String? tripCancelReason,
  String? startedAt,
  String? completedAt,
}) {
  final booking = _booking(status: status, tripStatus: tripStatus);
  return {
    ...booking,
    'cancelReason': cancelReason,
    'pickup': {'stopOrder': 1, 'name': 'Kadawatha', 'plannedAt': '2026-11-25T02:00:00.000Z'},
    'trip': {
      ...booking['trip'] as Map<String, dynamic>,
      'vehicle': {
        'type': 'VAN',
        'make': 'Toyota',
        'model': 'KDH',
        'year': 2018,
        'color': 'Silver',
        'plateNumber': plate,
      },
      'stops': [
        {'stopOrder': 1, 'name': 'Kadawatha', 'plannedAt': '2026-11-25T02:00:00.000Z'},
        {'stopOrder': 2, 'name': 'Kegalle', 'plannedAt': null},
        {'stopOrder': 3, 'name': 'Kandy', 'plannedAt': null},
      ],
      'startedAt': startedAt,
      'completedAt': completedAt,
      'cancelReason': tripCancelReason,
    },
  };
}

const _driver = {
  'id': 'd1',
  'fullName': 'Nimal S.',
  'photoUrl': null,
  'averageRating': 4.7,
  'ratingCount': 12,
  'completedTrips': 31,
  'verifiedDriver': true,
  'memberSince': '2026-11-01',
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
  Map<String, dynamic> details = _details();
  bool detailsFail = false;
  bool driverFails = false;
  http.Response Function()? onCancel;
  int mineCalls = 0;
  int detailsCalls = 0;

  http.Client get client => MockClient((request) async {
        final path = request.url.path.replaceFirst('/api/v1', '');
        if (path == '/trips/t1') return _ok({'trip': _trip});
        if (request.method == 'POST' && path == '/bookings') {
          sent['create'] = jsonDecode(request.body);
          return onCreate?.call(request) ?? _ok({'booking': _booking()}, 201);
        }
        if (path == '/bookings/b1') {
          detailsCalls++;
          return detailsFail ? _fail(500, 'INTERNAL_ERROR', 'Server down') : _ok({'booking': details});
        }
        if (path == '/drivers/d1') {
          return driverFails ? _fail(500, 'INTERNAL_ERROR', 'Server down') : _ok({'driver': _driver});
        }
        if (path == '/bookings/mine') {
          mineCalls++;
          final when = request.url.queryParameters['when'];
          return _ok({'bookings': when == 'upcoming' ? upcoming : <Object>[]});
        }
        if (request.method == 'POST' && path == '/bookings/b1/cancel') {
          sent['cancel'] = true;
          if (onCancel != null) return onCancel!();
          upcoming = [];
          details = _details(status: 'CANCELLED', plate: null);
          return _ok({'booking': _booking(status: 'CANCELLED')});
        }
        return _fail(404, 'NOT_FOUND', 'Not found');
      });

  ApiClient get api => ApiClient(baseUrl: 'http://test/api/v1', tokenProvider: () async => 't', httpClient: client);
}

Future<void> _pump(
  WidgetTester tester,
  _Server server,
  Widget Function(BookingApi api) screen, {
  Size size = const Size(800, 1800),
  double textScale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = server.api;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: AppServices(trips: TripRepository(api), child: child!),
    ),
    home: screen(BookingApi(api)),
  ));
  if (settle) await tester.pumpAndSettle();
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

    testWidgets('fits a 320 px wide screen with large text', (tester) async {
      final server = _Server()..upcoming = [_booking(tripStatus: 'CANCELLED'), _booking()];
      await _pump(tester, server, (api) => MyBookingsScreen(api: api), size: const Size(320, 3000), textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Trip cancelled'), findsOneWidget);
    });

    testWidgets('tapping a booking opens its details, and going back refreshes the list', (tester) async {
      final server = _Server();
      await _pump(tester, server, (api) => MyBookingsScreen(api: api));
      expect(server.mineCalls, 1);

      await tester.tap(find.text('Kadawatha → Kandy'));
      await tester.pumpAndSettle();
      expect(find.text('Booking details'), findsOneWidget);
      expect(find.text(_plate), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(server.mineCalls, 2);
      expect(find.textContaining('No upcoming bookings.'), findsOneWidget);
    });
  });

  group('BookingSuccessScreen', () {
    Widget screen(BookingApi api) => BookingSuccessScreen(api: api, booking: Booking.fromJson(_booking()));

    testWidgets('View details opens the booking', (tester) async {
      await _pump(tester, _Server(), screen);
      await tester.tap(find.text('View details'));
      await tester.pumpAndSettle();
      expect(find.text('Booking details'), findsOneWidget);
      expect(find.text(_plate), findsOneWidget);
    });

    testWidgets('View my bookings still works', (tester) async {
      await _pump(tester, _Server(), screen);
      await tester.tap(find.text('View my bookings'));
      await tester.pumpAndSettle();
      expect(find.text('My bookings'), findsOneWidget);
    });

    testWidgets('Done still closes the screen', (tester) async {
      await _pump(
        tester,
        _Server(),
        (api) => Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen(api))),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Booking confirmed'), findsNothing);
    });
  });

  group('booking details (SCRUM-83)', () {
    Widget screen(BookingApi api) => BookingDetailsScreen(api: api, bookingId: 'b1');

    test('old JSON without the new fields still parses', () {
      final b = Booking.fromJson(_booking());
      expect(b.vehicle, isNull);
      expect(b.stops, isEmpty);
      expect([b.startedAt, b.completedAt, b.tripCancelReason], [null, null, null]);

      final json = _booking();
      (json['trip'] as Map<String, dynamic>).remove('driverId');
      expect(Booking.fromJson(json).driverId, isNull);
    });

    testWidgets('shows the reference, journey, price, driver and vehicle', (tester) async {
      await _pump(tester, _Server(), screen);

      expect(find.text('BK-7Q2K9M'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      final pickupTime = DateTime.parse('2026-11-25T02:00:00.000Z').toLocal();
      expect(find.text(formatDateTime(pickupTime)), findsOneWidget);
      expect(find.widgetWithText(InfoRow, 'Kadawatha'), findsOneWidget);
      expect(find.widgetWithText(InfoRow, 'Kandy'), findsOneWidget);
      expect(find.text('Not given'), findsOneWidget); // the drop time
      final timeline = tester.widget<RouteTimeline>(find.byType(RouteTimeline));
      expect(timeline.stops.map((s) => s.name), ['Kadawatha', 'Kegalle', 'Kandy']);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('LKR 2,200'), findsOneWidget);
      expect(find.text('LKR 4,400'), findsOneWidget);
      expect(find.text('Nimal S.'), findsOneWidget);
      expect(find.text('4.7 (12)'), findsOneWidget);
      expect(find.text('Van'), findsOneWidget);
      expect(find.text('Toyota KDH'), findsOneWidget);
      expect(find.text(_plate), findsOneWidget);
    });

    for (final (status, tripStatus, label) in [
      ('CONFIRMED', 'SCHEDULED', 'Confirmed'),
      ('CONFIRMED', 'IN_PROGRESS', 'On the way'),
      ('CONFIRMED', 'COMPLETED', 'Completed'),
      ('CONFIRMED', 'CANCELLED', 'Trip cancelled'),
      ('CANCELLED', 'SCHEDULED', 'Cancelled'),
    ]) {
      testWidgets('status $status on a $tripStatus trip shows "$label"', (tester) async {
        await _pump(tester, _Server()..details = _details(status: status, tripStatus: tripStatus), screen);
        expect(find.widgetWithText(AppBadge, label), findsOneWidget);
        // Only a confirmed booking on a scheduled trip can be cancelled.
        expect(find.text('Cancel booking'), label == 'Confirmed' ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('shows the start and end times and both cancel reasons', (tester) async {
      final server = _Server()
        ..details = _details(
          tripStatus: 'CANCELLED',
          cancelReason: 'Plans changed',
          tripCancelReason: 'Car broke down',
          startedAt: '2026-11-25T01:35:00.000Z',
          completedAt: '2026-11-25T05:00:00.000Z',
        );
      await _pump(tester, server, screen);

      expect(find.text('Plans changed'), findsOneWidget);
      expect(find.text('Car broke down'), findsOneWidget);
      expect(find.text('Started'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('hides the plate when the server sends none', (tester) async {
      await _pump(tester, _Server()..details = _details(status: 'CANCELLED', plate: null), screen);
      expect(find.text('Plate number'), findsNothing);
      expect(find.text('Toyota KDH'), findsOneWidget);
    });

    testWidgets('works with an older server without the journey details', (tester) async {
      await _pump(tester, _Server()..details = _booking(), screen);
      final timeline = tester.widget<RouteTimeline>(find.byType(RouteTimeline));
      expect(timeline.stops.map((s) => s.name), ['Kadawatha', 'Kandy']);
      expect(find.text('Not available'), findsOneWidget);
    });

    testWidgets('shows a skeleton while loading, then an error with retry', (tester) async {
      final server = _Server()..detailsFail = true;
      await _pump(tester, server, screen, settle: false);
      expect(find.byType(SkeletonList), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('Server down'), findsOneWidget);

      server.detailsFail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('BK-7Q2K9M'), findsOneWidget);
    });

    testWidgets('a driver profile error does not break the screen', (tester) async {
      final server = _Server()..driverFails = true;
      await _pump(tester, server, screen);
      expect(find.text('Could not load the driver details.'), findsOneWidget);
      expect(find.text(_plate), findsOneWidget);

      server.driverFails = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Nimal S.'), findsOneWidget);
    });

    testWidgets('pull to refresh loads the booking again', (tester) async {
      final server = _Server();
      await _pump(tester, server, screen);
      server.details = _details(tripStatus: 'IN_PROGRESS');
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
      await tester.pumpAndSettle();
      expect(server.detailsCalls, 2);
      expect(find.text('On the way'), findsOneWidget);
    });

    testWidgets('cancelling asks first, then reloads this screen', (tester) async {
      final server = _Server();
      await _pump(tester, server, screen);

      await tester.tap(find.text('Cancel booking'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel booking BK-7Q2K9M?'), findsOneWidget);
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(server.sent['cancel'], isNull);

      await tester.tap(find.text('Cancel booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
      await tester.pumpAndSettle();

      expect(server.sent['cancel'], isTrue);
      expect(server.detailsCalls, 2);
      expect(find.widgetWithText(AppBadge, 'Cancelled'), findsOneWidget);
      expect(find.text(_plate), findsNothing);
      expect(find.text('Cancel booking'), findsNothing);
    });

    testWidgets('a failed cancel shows the error and keeps the booking', (tester) async {
      final server = _Server()
        ..onCancel = () => _fail(409, 'TRIP_NOT_CANCELLABLE', 'A booking on this trip cannot be cancelled');
      await _pump(tester, server, screen);

      await tester.tap(find.text('Cancel booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
      await tester.pumpAndSettle();

      expect(find.text('A booking on this trip cannot be cancelled'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancel booking')).enabled, isTrue);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('fits a 320 px wide screen at text scale $scale', (tester) async {
        final server = _Server()..details = _details(cancelReason: 'Plans changed', tripCancelReason: 'Car broke down');
        await _pump(tester, server, screen, size: const Size(320, 8000), textScale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text(_plate), findsOneWidget);
        expect(find.text('Cancel booking'), findsOneWidget);
      });
    }
  });
}
