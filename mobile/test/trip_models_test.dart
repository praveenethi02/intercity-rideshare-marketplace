import 'package:flutter_test/flutter_test.dart';
import 'package:rideshare_mobile/features/trips/trips.dart';

Map<String, dynamic> tripJson({String status = 'SCHEDULED', List<int> reserved = const [0, 0, 0]}) => {
      'id': 't1',
      'driverId': 'd1',
      'vehicleId': 'v1',
      'pricingMode': 'FIXED',
      'status': status,
      'departureAt': '2026-11-20T00:30:00.000Z',
      'estimatedArrivalAt': null,
      'seatsOffered': 3,
      'basePriceCents': 250000,
      'distanceKm': 122.2,
      'originName': 'Colombo Fort',
      'destinationName': 'Kandy',
      'allowsCargo': false,
      'cargoCapacityKg': null,
      'notes': null,
      'stops': [
        {'order': 0, 'name': 'Colombo Fort', 'lat': 6.9344, 'lng': 79.8428, 'distanceFromStartKm': 0, 'plannedAt': '2026-11-20T00:30:00.000Z'},
        {'order': 1, 'name': 'Kadawatha', 'lat': 7.001, 'lng': 79.953, 'distanceFromStartKm': 15.6, 'plannedAt': null},
        {'order': 2, 'name': 'Kegalle', 'lat': 7.2513, 'lng': 80.3464, 'distanceFromStartKm': 80.1, 'plannedAt': null},
        {'order': 3, 'name': 'Kandy', 'lat': 7.2906, 'lng': 80.6337, 'distanceFromStartKm': 122.24, 'plannedAt': null},
      ],
      'legs': [
        for (var i = 0; i < reserved.length; i++)
          {'legIndex': i, 'seatsReserved': reserved[i], 'seatsAvailable': 3 - reserved[i]},
      ],
      'seatsAvailable': 3,
    };

void main() {
  test('Trip.fromJson parses stops, legs and labels', () {
    final t = Trip.fromJson(tripJson());
    expect(t.stops.length, 4);
    expect(t.legs.length, 3);
    expect(t.routeLabel, 'Colombo Fort → Kandy');
    expect(t.legLabel(1), 'Kadawatha → Kegalle');
    expect(t.totalDistanceKm, 122.2);
    expect(t.stops[0].kmFromStart, 0.0); // int 0 from JSON becomes double
  });

  test('edit mode follows backend rules', () {
    expect(Trip.fromJson(tripJson(status: 'DRAFT')).editMode, TripEditMode.full);
    expect(Trip.fromJson(tripJson()).editMode, TripEditMode.limited);
    expect(Trip.fromJson(tripJson(reserved: [0, 2, 0])).editMode, TripEditMode.notesOnly);
    expect(Trip.fromJson(tripJson(status: 'COMPLETED')).editMode, TripEditMode.none);
  });

  test('start allowed only within 30 minutes of departure', () {
    final t = Trip.fromJson(tripJson());
    expect(t.canStartAt(t.departureTime.subtract(const Duration(minutes: 31))), isFalse);
    expect(t.canStartAt(t.departureTime.subtract(const Duration(minutes: 30))), isTrue);
    expect(t.canStartAt(t.departureTime.add(const Duration(minutes: 5))), isTrue);
  });

  test('list items use origin/destination names when there are no stops', () {
    final json = tripJson()
      ..remove('stops')
      ..['originName'] = 'Galle'
      ..['destinationName'] = 'Matara';
    expect(Trip.fromJson(json).routeLabel, 'Galle → Matara');
  });

  test('search result parses pickup/drop', () {
    final r = TripSearchResult.fromJson({
      'tripId': 't1',
      'driverId': 'd1',
      'vehicleId': 'v1',
      'pricingMode': 'AUCTION',
      'departureAt': '2026-11-20T00:30:00.000Z',
      'allowsCargo': true,
      'pickup': {'stopOrder': 1, 'name': 'Kadawatha', 'lat': 7.001, 'lng': 79.953, 'plannedAt': null, 'distanceFromYouKm': 0.3},
      'drop': {'stopOrder': 2, 'name': 'Kegalle', 'lat': 7.2513, 'lng': 80.3464, 'plannedAt': null, 'distanceFromYourDestinationKm': 1.2},
      'segmentDistanceKm': 64.5,
      'seatsAvailable': 2,
      'segmentPriceCents': 132000,
    });
    expect(r.pickup.order, 1);
    expect(r.drop.order, 2);
    expect(r.walkingKm, closeTo(1.5, 1e-9));
    expect(r.pickupTime, r.departureTime);
  });

  test('TripRules', () {
    final now = DateTime(2026, 11, 5, 10);
    expect(TripRules.checkDeparture(now.add(const Duration(minutes: 10)), now), isNotNull);
    expect(TripRules.checkDeparture(now.add(const Duration(hours: 2)), now), isNull);
    expect(TripRules.checkDeparture(now.add(const Duration(days: 61)), now), isNotNull);
    const a = TripStop(name: 'A', lat: 1, lng: 1);
    const b = TripStop(name: 'B', lat: 2, lng: 2);
    expect(TripRules.checkStops([a]), isNotNull);
    expect(TripRules.checkStops([a, a]), isNotNull);
    expect(TripRules.checkStops([a, b, a]), isNull);
  });

  test('TripDraft.toJson sends UTC times and skips empty optionals', () {
    final draft = TripDraft(
      vehicleId: 'v1',
      pricingMode: PricingMode.fixed,
      departureTime: DateTime.utc(2026, 11, 20, 0, 30),
      seatsOffered: 3,
      basePriceCents: 250000,
      notes: '  ',
      stops: const [TripStop(name: 'A', lat: 1, lng: 1), TripStop(name: 'B', lat: 2, lng: 2)],
    );
    final json = draft.toJson();
    expect(json['departureAt'], '2026-11-20T00:30:00.000Z');
    expect(json.containsKey('notes'), isFalse);
    expect(json.containsKey('cargoCapacityKg'), isFalse);
    expect((json['stops'] as List).length, 2);
  });
}
