// SCRUM-296: while a page loads, it shows a skeleton instead of a full-screen spinner.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rideshare_mobile/core/api_client.dart';
import 'package:rideshare_mobile/core/app_services.dart';
import 'package:rideshare_mobile/core/theme/app_theme.dart';
import 'package:rideshare_mobile/core/widgets/app_components.dart';
import 'package:rideshare_mobile/features/driver/driver.dart';
import 'package:rideshare_mobile/features/trips/trips.dart';
import 'package:rideshare_mobile/features/vehicle/screens/vehicle_documents_screen.dart';
import 'package:rideshare_mobile/features/vehicle/screens/vehicle_form_screen.dart';
import 'package:rideshare_mobile/features/vehicle/screens/vehicle_verification_screen.dart';
import 'package:rideshare_mobile/features/vehicle/vehicle.dart';

/// A fake server that holds every answer until [open] is called, so the test can look at the
/// screen while it is still loading.
class _SlowServer {
  final Object? Function(http.Request request) data;
  final Object? meta;
  final _gate = Completer<void>();
  _SlowServer(this.data, {this.meta});

  void open() => _gate.complete();

  ApiClient get api => ApiClient(
        baseUrl: 'http://test/api/v1',
        tokenProvider: () async => 't',
        httpClient: MockClient((request) async {
          await _gate.future;
          return http.Response(
            jsonEncode({'success': true, 'message': 'OK', 'data': data(request), 'meta': meta}),
            200,
          );
        }),
      );
}

/// Shows [screen], checks that [skeleton] is shown while loading and no spinner, then lets the
/// server answer and checks that [content] replaced the skeleton.
Future<void> _expectSkeletonThenContent(
  WidgetTester tester,
  _SlowServer server,
  Widget screen, {
  required Type skeleton,
  required Finder content,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => AppServices(trips: TripRepository(server.api), child: child!),
    home: screen,
  ));
  await tester.pump();

  expect(find.byType(skeleton), findsOneWidget);
  expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);

  server.open();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  expect(find.byType(skeleton), findsNothing);
  expect(content, findsWidgets);
  expect(tester.takeException(), isNull);
}

DriverRepository _drivers(_SlowServer server) => DriverRepository(server.api);
VehicleApi _vehicles(_SlowServer server) => VehicleApi(server.api);

Map<String, dynamic> _driver() => {
      'id': 'user-1',
      'userId': 'user-1',
      'licenceNumber': 'B1234567',
      'licenceExpiry': '2099-01-31',
      'dateOfBirth': '1995-03-10',
      'address': '12 Kandy Road',
      'emergencyContactName': 'Kamal Silva',
      'emergencyContactPhone': '+94771234567',
      'verification': 'PENDING',
      'rejectionReason': null,
      'verifiedAt': null,
      'accountStatus': 'ACTIVE',
      'averageRating': 4.5,
      'ratingCount': 2,
      'completedTrips': 3,
      'documents': [],
    };

Map<String, dynamic> _trip({String status = 'SCHEDULED'}) => {
      'id': 't1',
      'driverId': 'd1',
      'vehicleId': 'v1',
      'pricingMode': 'FIXED',
      'status': status,
      'departureAt': '2026-11-27T00:30:00.000Z',
      'seatsOffered': 3,
      'basePriceCents': 250000,
      'distanceKm': 115,
      'stops': [
        {'order': 0, 'name': 'Colombo Fort', 'lat': 6.93, 'lng': 79.84, 'distanceFromStartKm': 0},
        {'order': 1, 'name': 'Kandy', 'lat': 7.29, 'lng': 80.63, 'distanceFromStartKm': 115},
      ],
    };

Map<String, dynamic> _vehicle() => {
      'id': 'v1',
      'vehicleType': 'CAR',
      'make': 'Toyota',
      'model': 'Axio',
      'year': 2016,
      'color': 'White',
      'plateNumber': 'WP CAB-1234',
      'totalSeats': 5,
      'passengerSeats': 4,
      'cargoCapacityKg': 0,
      'cargoVolumeL': 0,
      'verificationStatus': 'NOT_SUBMITTED',
      'rejectionReason': null,
      'isActive': true,
    };

const _vehicleTypes = [
  {
    'type': 'CAR',
    'label': 'Car',
    'minSeats': 2,
    'maxSeats': 5,
    'maxCargoKg': 100,
    'maxCargoVolumeL': 500,
    'allowsCargo': true,
    'brands': [
      {
        'name': 'Toyota',
        'models': ['Axio'],
      },
    ],
  },
];

void main() {
  group('driver screens', () {
    testWidgets('DriverHomeScreen', (tester) async {
      final server = _SlowServer((_) => {'driver': _driver()});
      await _expectSkeletonThenContent(tester, server, DriverHomeScreen(repository: _drivers(server)),
          skeleton: SkeletonDetail, content: find.text('0 of 5 uploaded'));
    });

    testWidgets('DriverDocumentsScreen', (tester) async {
      final server = _SlowServer((_) => {'driver': _driver()});
      await _expectSkeletonThenContent(tester, server, DriverDocumentsScreen(repository: _drivers(server)),
          skeleton: SkeletonList, content: find.text('0 of 5 uploaded'));
    });

    testWidgets('DriverEarningsScreen', (tester) async {
      final server = _SlowServer((_) => {
            'earnings': {
              'currency': 'LKR',
              'seatEarnings': 0,
              'cargoEarnings': 0,
              'platformFees': 0,
              'paidOut': 0,
              'pendingPayout': 0,
              'completedTrips': 3,
            },
          });
      await _expectSkeletonThenContent(tester, server, DriverEarningsScreen(repository: _drivers(server)),
          skeleton: SkeletonDetail, content: find.text('Seat earnings'));
    });

    testWidgets('DriverTripHistoryScreen', (tester) async {
      final server = _SlowServer(
        (_) => {
          'trips': [
            {'id': 't1', 'originName': 'Kandy', 'destinationName': 'Colombo', 'status': 'COMPLETED'},
          ],
        },
        meta: {'page': 1, 'limit': 20, 'total': 1, 'totalPages': 1},
      );
      await _expectSkeletonThenContent(tester, server, DriverTripHistoryScreen(repository: _drivers(server)),
          skeleton: SkeletonList, content: find.text('Kandy → Colombo'));
    });

    testWidgets('DriverVerificationScreen', (tester) async {
      final server = _SlowServer((_) => {
            'verification': {
              'id': null,
              'status': 'PENDING',
              'reason': null,
              'missingDocuments': ['PROFILE_PHOTO'],
              'documents': [],
              'submittedAt': null,
              'decidedAt': null,
            },
          });
      await _expectSkeletonThenContent(tester, server, DriverVerificationScreen(repository: _drivers(server)),
          skeleton: SkeletonDetail, content: find.text('Profile photo'));
    });
  });

  group('trip screens', () {
    testWidgets('DriverTripsScreen', (tester) async {
      final server = _SlowServer((_) => {
            'trips': [_trip()],
          });
      await _expectSkeletonThenContent(tester, server, const DriverTripsScreen(),
          skeleton: SkeletonList, content: find.text('Colombo Fort → Kandy'));
    });

    testWidgets('DriverTripDetailScreen', (tester) async {
      final server = _SlowServer((_) => {'trip': _trip()});
      await _expectSkeletonThenContent(tester, server, const DriverTripDetailScreen(tripId: 't1'),
          skeleton: SkeletonDetail, content: find.text('Colombo Fort → Kandy'));
    });

    testWidgets('ActiveTripScreen', (tester) async {
      final server = _SlowServer((_) => {'trip': _trip(status: 'IN_PROGRESS')});
      await _expectSkeletonThenContent(tester, server, const ActiveTripScreen(tripId: 't1'),
          skeleton: SkeletonDetail, content: find.text('Colombo Fort → Kandy'));
    });

    testWidgets('SavedRoutesScreen', (tester) async {
      final server = _SlowServer((_) => {
            'savedRoutes': [
              {
                'id': 'r1',
                'name': 'Weekend home',
                'stops': _trip()['stops'],
              },
            ],
          });
      await _expectSkeletonThenContent(tester, server, const SavedRoutesScreen(),
          skeleton: SkeletonList, content: find.text('Weekend home'));
    });
  });

  group('vehicle screens', () {
    testWidgets('VehicleDocumentsScreen', (tester) async {
      final server = _SlowServer((_) => []);
      await _expectSkeletonThenContent(tester, server, VehicleDocumentsScreen(api: _vehicles(server), vehicleId: 'v1'),
          skeleton: SkeletonList, content: find.textContaining('required document(s) still needed'));
    });

    testWidgets('VehicleVerificationScreen', (tester) async {
      final server = _SlowServer((_) => {'status': 'NOT_SUBMITTED', 'missingDocuments': [], 'rejectionReason': null});
      await _expectSkeletonThenContent(
          tester, server, VehicleVerificationScreen(api: _vehicles(server), vehicleId: 'v1'),
          skeleton: SkeletonDetail, content: find.text('Submit for review'));
    });

    testWidgets('VehicleFormScreen', (tester) async {
      final server =
          _SlowServer((request) => request.url.path.endsWith('/vehicles/types') ? _vehicleTypes : _vehicle());
      await _expectSkeletonThenContent(tester, server, VehicleFormScreen(api: _vehicles(server), vehicleId: 'v1'),
          skeleton: SkeletonDetail, content: find.widgetWithText(TextFormField, 'Plate number'));
    });
  });

  testWidgets('SkeletonDetail fits a 320 px wide screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const Scaffold(body: SkeletonDetail(cards: 4))));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
