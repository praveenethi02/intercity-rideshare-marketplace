import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rideshare_mobile/core/api_client.dart';
import 'package:rideshare_mobile/features/vehicle/screens/vehicle_form_screen.dart';
import 'package:rideshare_mobile/features/vehicle/vehicle.dart';

http.Response _ok(Object? data, [int status = 200]) =>
    http.Response(jsonEncode({'success': true, 'message': 'OK', 'data': data, 'meta': null}), status);

const _types = [
  {
    'type': 'CAR',
    'label': 'Car',
    'minSeats': 2,
    'maxSeats': 5,
    'maxCargoKg': 100,
    'maxCargoVolumeL': 500,
    'allowsCargo': true,
    'brands': [
      {'name': 'Suzuki', 'models': ['Alto', 'Wagon R']},
      {'name': 'Toyota', 'models': ['Axio', 'Premio']},
    ],
  },
  {
    'type': 'THREE_WHEELER',
    'label': 'Three-wheeler',
    'minSeats': 2,
    'maxSeats': 4,
    'maxCargoKg': 150,
    'maxCargoVolumeL': 300,
    'allowsCargo': true,
    'brands': [
      {'name': 'Bajaj', 'models': ['RE']},
    ],
  },
];

Map<String, dynamic> _vehicle(String make, String model) => {
      'id': 'v1',
      'vehicleType': 'CAR',
      'make': make,
      'model': model,
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

class _Server {
  final Map<String, Object?> sent = {};
  final Map<String, dynamic>? existing;
  _Server({this.existing});

  http.Client get client => MockClient((request) async {
        final path = request.url.path.replaceFirst('/api/v1', '');
        if (path == '/vehicles/types') return _ok(_types);
        if (request.method == 'GET' && path == '/vehicles/v1') return _ok(existing);
        sent['${request.method} $path'] = jsonDecode(request.body);
        return _ok(_vehicle('x', 'y'), request.method == 'POST' ? 201 : 200);
      });
}

Future<void> _pump(WidgetTester tester, _Server server, {String? vehicleId}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = VehicleApi(ApiClient(baseUrl: 'http://test/api/v1', tokenProvider: () async => 't', httpClient: server.client));
  await tester.pumpWidget(MaterialApp(
    home: VehicleFormScreen(api: api, vehicleId: vehicleId),
    onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Documents'))),
  ));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String field, String option) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, field));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> _fillRest(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Plate number'), 'WP CAB-1234');
  await tester.enterText(find.widgetWithText(TextFormField, 'Year'), '2016');
  await tester.enterText(find.widgetWithText(TextFormField, 'Colour'), 'White');
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Add vehicle'));
  await tester.pumpAndSettle();
}

void main() {
  test('seatRange shows one number when the range has one value', () {
    expect(seatRange(2, 5), '2-5 seats');
    expect(seatRange(2, 2), '2 seats');
  });

  testWidgets('sends the brand and model chosen from the lists', (tester) async {
    final server = _Server();
    await _pump(tester, server);

    await _choose(tester, 'Brand', 'Toyota');
    await _choose(tester, 'Model', 'Premio');
    await _fillRest(tester);
    await _save(tester);

    final body = server.sent['POST /vehicles'] as Map<String, dynamic>;
    expect(body['make'], 'Toyota');
    expect(body['model'], 'Premio');
  });

  testWidgets('"Other" brand asks for the brand and model names', (tester) async {
    final server = _Server();
    await _pump(tester, server);

    await _choose(tester, 'Brand', 'Other (type the name)');
    expect(find.widgetWithText(DropdownButtonFormField<String>, 'Model'), findsNothing);
    await tester.enterText(find.widgetWithText(TextFormField, 'Brand name'), 'Mahindra');
    await tester.enterText(find.widgetWithText(TextFormField, 'Model name'), 'KUV100');
    await _fillRest(tester);
    await _save(tester);

    final body = server.sent['POST /vehicles'] as Map<String, dynamic>;
    expect(body['make'], 'Mahindra');
    expect(body['model'], 'KUV100');
  });

  testWidgets('"Other" model keeps the brand and asks for the model name', (tester) async {
    final server = _Server();
    await _pump(tester, server);

    await _choose(tester, 'Brand', 'Suzuki');
    await _choose(tester, 'Model', 'Other (type the name)');
    await tester.enterText(find.widgetWithText(TextFormField, 'Model name'), 'Every');
    await _fillRest(tester);
    await _save(tester);

    final body = server.sent['POST /vehicles'] as Map<String, dynamic>;
    expect(body['make'], 'Suzuki');
    expect(body['model'], 'Every');
  });

  testWidgets('asks for a brand and model before saving', (tester) async {
    final server = _Server();
    await _pump(tester, server);

    await _fillRest(tester);
    await _save(tester);

    expect(find.text('Choose a brand'), findsWidgets);
    expect(server.sent, isEmpty);
  });

  testWidgets('changing to a type without the chosen brand clears it', (tester) async {
    final server = _Server();
    await _pump(tester, server);

    await _choose(tester, 'Brand', 'Toyota');
    await _choose(tester, 'Vehicle type', 'Three-wheeler (2-4 seats)');

    expect(find.text('Toyota'), findsNothing);
    await _choose(tester, 'Brand', 'Bajaj');
    await _choose(tester, 'Model', 'RE');
    await _fillRest(tester);
    await _save(tester);

    final body = server.sent['POST /vehicles'] as Map<String, dynamic>;
    expect(body, containsPair('vehicleType', 'THREE_WHEELER'));
    expect(body, containsPair('make', 'Bajaj'));
  });

  testWidgets('editing a vehicle whose make is not in the list shows it under "Other"', (tester) async {
    final server = _Server(existing: _vehicle('Mahindra', 'KUV100'));
    await _pump(tester, server, vehicleId: 'v1');

    expect(find.text('Other (type the name)'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Mahindra'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'KUV100'), findsOneWidget);
  });

  testWidgets('editing a vehicle from the list selects its brand and model', (tester) async {
    final server = _Server(existing: _vehicle('Toyota', 'Axio'));
    await _pump(tester, server, vehicleId: 'v1');

    expect(find.text('Toyota'), findsOneWidget);
    expect(find.text('Axio'), findsOneWidget);
    expect(find.text('Other (type the name)'), findsNothing);
  });
}
