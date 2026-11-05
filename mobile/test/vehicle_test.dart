import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rideshare_mobile/core/api_client.dart';
import 'package:rideshare_mobile/core/app_services.dart';
import 'package:rideshare_mobile/features/trips/trips.dart';
import 'package:rideshare_mobile/features/vehicle/screens/vehicle_list_screen.dart';
import 'package:rideshare_mobile/features/vehicle/screens/vehicle_verification_screen.dart';
import 'package:rideshare_mobile/features/vehicle/vehicle.dart';

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'success': true, 'message': 'OK', 'data': data, 'meta': null}), 200);

Map<String, dynamic> _json({String status = 'APPROVED', bool active = true, int passengerSeats = 4, String id = 'v1'}) => {
      'id': id,
      'vehicleType': 'CAR',
      'make': 'Toyota',
      'model': 'Axio',
      'year': 2016,
      'color': 'White',
      'plateNumber': 'WP CAB-1234',
      'totalSeats': 5,
      'passengerSeats': passengerSeats,
      'cargoCapacityKg': 0,
      'cargoVolumeL': 0,
      'verificationStatus': status,
      'rejectionReason': null,
      'isActive': active,
    };

Vehicle _vehicle({String status = 'APPROVED', bool active = true, String id = 'v1'}) =>
    Vehicle.fromJson(_json(status: status, active: active, id: id));

ApiClient _client(MockClientHandler handler) =>
    ApiClient(baseUrl: 'http://10.0.2.2:4000/api/v1', tokenProvider: () async => 'token', httpClient: MockClient(handler));

void main() {
  group('usableVehicle', () {
    test('picks the first approved, active vehicle', () {
      final picked = usableVehicle([
        _vehicle(status: 'PENDING', id: 'a'),
        _vehicle(active: false, id: 'b'),
        _vehicle(id: 'c'),
        _vehicle(id: 'd'),
      ]);
      expect(picked?.id, 'c');
    });

    test('returns null when no vehicle can be used', () {
      expect(usableVehicle([]), isNull);
      expect(usableVehicle([_vehicle(status: 'REJECTED'), _vehicle(active: false)]), isNull);
    });
  });

  test('noUsableVehicleMessage explains the reason', () {
    expect(noUsableVehicleMessage([]), contains('no vehicles'));
    expect(noUsableVehicleMessage([_vehicle(status: 'PENDING')]), contains('waiting for admin approval'));
    expect(noUsableVehicleMessage([_vehicle(active: false)]), contains('not active'));
    expect(noUsableVehicleMessage([_vehicle(status: 'REJECTED')]), contains('no approved vehicle'));
  });

  group('VehicleApi', () {
    test('myVehicles reads the list from /vehicles/mine', () async {
      late Uri called;
      final api = VehicleApi(_client((req) async {
        called = req.url;
        return _ok([_json()]);
      }));
      final vehicles = await api.myVehicles();
      expect(called.path, '/api/v1/vehicles/mine');
      expect(vehicles.single.plateNumber, 'WP CAB-1234');
    });

    test('uploadDocument sends docType and the file as multipart', () async {
      late http.Request sent;
      final api = VehicleApi(_client((req) async {
        sent = req;
        return _ok({'id': 'd1', 'docType': 'INSURANCE', 'fileUrl': 'http://x/a.pdf?sig=1', 'status': 'UPLOADED'});
      }));
      final doc = await api.uploadDocument('v1', 'INSURANCE', [1, 2, 3], 'a.pdf');
      expect(sent.url.path, '/api/v1/vehicles/v1/documents');
      expect(sent.headers['content-type'], startsWith('multipart/form-data'));
      expect(sent.body, contains('name="docType"'));
      expect(doc.isPdf, isTrue);
    });
  });

  group('vehicleRoute', () {
    final api = VehicleApi(_client((_) async => _ok([])));

    test('knows the vehicle paths and ignores others', () {
      for (final path in [
        '/vehicles',
        '/vehicles/new',
        '/vehicles/abc/edit',
        '/vehicles/abc/documents',
        '/vehicles/abc/verification',
      ]) {
        expect(vehicleRoute(RouteSettings(name: path), api), isNotNull, reason: path);
      }
      expect(vehicleRoute(const RouteSettings(name: '/trips'), api), isNull);
      expect(vehicleRoute(const RouteSettings(name: '/vehicles/abc/unknown'), api), isNull);
    });
  });

  testWidgets('VehicleListScreen shows vehicles and why one cannot be used', (tester) async {
    final api = VehicleApi(_client((_) async => _ok([_json(status: 'PENDING')])));
    await tester.pumpWidget(MaterialApp(home: VehicleListScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('WP CAB-1234'), findsOneWidget);
    expect(find.text('Pending review'), findsOneWidget);
    expect(find.textContaining('cannot be used for trips'), findsOneWidget);
  });

  testWidgets('VehicleVerificationScreen submits and shows the new status', (tester) async {
    var status = 'NOT_SUBMITTED';
    Map<String, dynamic> info() => {'status': status, 'missingDocuments': <String>[], 'rejectionReason': null};
    final api = VehicleApi(_client((req) async {
      if (req.method == 'POST') status = 'PENDING';
      return _ok(info());
    }));
    await tester.pumpWidget(MaterialApp(home: VehicleVerificationScreen(api: api, vehicleId: 'v1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit for review'));
    await tester.pumpAndSettle();

    expect(find.text('Pending review'), findsOneWidget);
    expect(find.text('Submitted for review'), findsOneWidget);
    expect(find.textContaining('setState'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('VehicleListScreen reloads after returning from another screen', (tester) async {
    var status = 'NOT_SUBMITTED';
    final api = VehicleApi(_client((_) async => _ok([_json(status: status)])));
    await tester.pumpWidget(MaterialApp(
      home: VehicleListScreen(api: api),
      onGenerateRoute: (settings) => vehicleRoute(settings, api),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Not submitted'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    status = 'PENDING';
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Pending review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('DriverTripsScreen', () {
    Future<VehicleApi> pump(WidgetTester tester, {required Future<String?> Function() check, String? vehicleId}) async {
      final client = _client((req) async => _ok(req.url.path.contains('vehicles') ? [_json()] : []));
      final api = VehicleApi(client);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => AppServices(
          trips: TripRepository(client),
          driverVehicleId: vehicleId,
          vehicleSeatCapacity: vehicleId == null ? null : 5,
          checkDriverVehicle: check,
          child: child!,
        ),
        onGenerateRoute: (settings) => vehicleRoute(settings, api),
        home: const DriverTripsScreen(),
      ));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('a driver with no approved vehicle sees why and cannot create a trip', (tester) async {
      await pump(tester, check: () async => 'Your vehicle is waiting for admin approval.');
      await tester.tap(find.text('New trip'));
      await tester.pumpAndSettle();
      expect(find.text('Your vehicle is waiting for admin approval.'), findsOneWidget);
      expect(find.byType(CreateTripScreen), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(CreateTripScreen), findsNothing);
    });

    testWidgets('a driver with an approved vehicle reaches the create trip screen', (tester) async {
      await pump(tester, check: () async => null, vehicleId: 'v1');
      await tester.tap(find.text('New trip'));
      await tester.pumpAndSettle();
      expect(find.byType(CreateTripScreen), findsOneWidget);
    });

    testWidgets('the My vehicles button opens the vehicle list', (tester) async {
      var checks = 0;
      await pump(tester, check: () async {
        checks++;
        return null;
      });
      await tester.tap(find.byTooltip('My vehicles'));
      await tester.pumpAndSettle();
      expect(find.byType(VehicleListScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(checks, 1, reason: 'the vehicle is reloaded after returning');
    });
  });
}
