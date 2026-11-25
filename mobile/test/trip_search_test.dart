import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rideshare_mobile/core/api_client.dart';
import 'package:rideshare_mobile/core/app_services.dart';
import 'package:rideshare_mobile/core/formatters.dart';
import 'package:rideshare_mobile/core/theme/app_theme.dart';
import 'package:rideshare_mobile/features/trips/data/towns.dart';
import 'package:rideshare_mobile/features/trips/trips.dart';
import 'package:rideshare_mobile/features/trips/widgets/search_result_card.dart';

http.Response _ok(Object? data, {Map<String, Object?>? meta}) =>
    http.Response(jsonEncode({'success': true, 'message': 'OK', 'data': data, 'meta': meta}), 200);

http.Response _fail(int status, String code, String message) => http.Response(
      jsonEncode({
        'success': false,
        'message': message,
        'data': null,
        'meta': {'code': code}
      }),
      status,
    );

TripStop _town(String name) => kTowns.firstWhere((t) => t.name == name);

/// A search result as GET /trips/search returns it. Optional fields can be left out, as older
/// servers do.
Map<String, dynamic> _result(
  String id, {
  String pickup = 'Kadawatha',
  int seatsAvailable = 2,
  int? seatsOffered = 3,
  int price = 132000,
  bool cargo = false,
  double? cargoKg,
  String? dropAt,
  String? arrivalAt,
  bool newFields = true,
}) =>
    {
      'tripId': id,
      'driverId': 'd1',
      'vehicleId': 'v1',
      'pricingMode': 'FIXED',
      'departureAt': '2026-11-27T00:30:00.000Z',
      'allowsCargo': cargo,
      'pickup': {
        'stopOrder': 1,
        'name': pickup,
        'lat': 7.001,
        'lng': 79.953,
        'plannedAt': null,
        'distanceFromYouKm': 0.3,
      },
      'drop': {
        'stopOrder': 3,
        'name': 'Kandy',
        'lat': 7.29,
        'lng': 80.63,
        'plannedAt': dropAt,
        'distanceFromYourDestinationKm': 1.2,
      },
      'segmentDistanceKm': 64.5,
      'seatsAvailable': seatsAvailable,
      'segmentPriceCents': price,
      if (newFields) ...{
        'seatsOffered': seatsOffered,
        'estimatedArrivalAt': arrivalAt,
        'cargoCapacityKg': cargoKg,
      },
    };

/// A fake backend for GET /trips/search. It records every query and answers with [respond].
class _SearchServer {
  final List<Map<String, String>> queries = [];
  late Future<http.Response> Function(Map<String, String> query) respond = (q) async => page(q, total: 0);

  /// Results `0 .. total-1`, sliced like the real API (page, limit), named "Stop <i>".
  static http.Response page(Map<String, String> q, {required int total}) {
    final p = int.parse(q['page'] ?? '1');
    final limit = int.parse(q['limit'] ?? '20');
    final start = (p - 1) * limit;
    final end = (start + limit).clamp(0, total).toInt();
    final results = [for (var i = start; i < end; i++) _result('t$i', pickup: 'Stop $i')];
    return _ok({'results': results}, meta: {'page': p, 'limit': limit, 'total': total, 'radiusKm': 5});
  }

  ApiClient get api => ApiClient(
        baseUrl: 'http://test/api/v1',
        tokenProvider: () async => 't',
        httpClient: MockClient((request) async {
          final path = request.url.path.replaceFirst('/api/v1', '');
          if (path == '/trips/search') {
            queries.add(request.url.queryParameters);
            return respond(request.url.queryParameters);
          }
          return _fail(404, 'NOT_FOUND', 'Not found');
        }),
      );

  Map<String, String> get last => queries.last;
}

final _query = SearchQuery(from: _town('Colombo Fort'), to: _town('Kandy'), date: DateTime(2026, 11, 27), seats: 2);

Future<void> _pump(WidgetTester tester, ApiClient api, Widget home, {Size size = const Size(800, 1800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => AppServices(trips: TripRepository(api), child: child!),
    home: home,
  ));
  await tester.pumpAndSettle();
}

/// Taps a sort chip and waits for the new results.
Future<void> _tapChip(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ChoiceChip, label));
  await tester.pumpAndSettle();
}

void main() {
  group('models', () {
    test('SearchQuery sends filters and sort, and leaves out empty filters', () {
      expect(_query.toQuery(), allOf(containsPair('sort', 'earliest'), containsPair('limit', '20')));
      expect(_query.toQuery().keys, isNot(contains('maxPriceCents')));
      expect(_query.toQuery().keys, isNot(contains('allowsCargo')));

      final q = _query.copyWith(
        sort: SearchSort.cheapest,
        filters: const SearchFilters(
          maxPriceCents: 150000,
          departAfter: '06:00',
          departBefore: '09:30',
          allowsCargo: true,
          minCargoKg: 50,
        ),
      );
      expect(q.toQuery(page: 3), {
        'fromLat': '${_town('Colombo Fort').lat}',
        'fromLng': '${_town('Colombo Fort').lng}',
        'toLat': '${_town('Kandy').lat}',
        'toLng': '${_town('Kandy').lng}',
        'date': '2026-11-27',
        'seats': '2',
        'maxPriceCents': '150000',
        'departAfter': '06:00',
        'departBefore': '09:30',
        'allowsCargo': 'true',
        'minCargoKg': '50',
        'sort': 'cheapest',
        'page': '3',
        'limit': '20',
      });
      expect(q.filters.activeCount, 4); // the departure range counts once
      expect(const SearchFilters(minCargoKg: 12.5).toQuery(), {'minCargoKg': '12.5'});
    });

    test('isSamePlace: the same town, or another name with the same coordinates', () {
      final kandy = _town('Kandy');
      expect(isSamePlace(kandy, kandy), isTrue);
      expect(isSamePlace(kandy, TripStop(name: 'My place', lat: kandy.lat, lng: kandy.lng)), isTrue);
      expect(isSamePlace(kandy, const TripStop(name: ' kandy ', lat: 0, lng: 0)), isTrue);
      expect(isSamePlace(kandy, _town('Katugastota')), isFalse);
    });

    test('recent searches keep the last five, newest first, without duplicates', () {
      final recent = RecentSearches();
      final towns = ['Kadawatha', 'Kegalle', 'Kandy', 'Galle', 'Matara', 'Jaffna'];
      for (final name in towns) {
        recent.add(SearchQuery(from: _town('Colombo Fort'), to: _town(name), date: DateTime(2026, 12, 1)));
      }
      expect(recent.items.map((q) => q.to.name), ['Jaffna', 'Matara', 'Galle', 'Kandy', 'Kegalle']);

      recent.add(SearchQuery(from: _town('Colombo Fort'), to: _town('Kandy'), date: DateTime(2026, 12, 1)));
      expect(recent.items.map((q) => q.to.name), ['Kandy', 'Jaffna', 'Matara', 'Galle', 'Kegalle']);
    });

    test('new search fields are read, and are optional for older servers', () {
      final r = TripSearchResult.fromJson(
        _result('t1', seatsOffered: 4, cargo: true, cargoKg: 120.5, arrivalAt: '2026-11-27T04:00:00.000Z'),
      );
      expect(r.seatsOffered, 4);
      expect(r.cargoCapacityKg, 120.5);
      expect(r.estimatedArrivalTime, DateTime.parse('2026-11-27T04:00:00.000Z').toLocal());

      final old = TripSearchResult.fromJson(_result('t1', newFields: false));
      expect(old.seatsOffered, isNull);
      expect(old.cargoCapacityKg, isNull);
      expect(old.estimatedArrivalTime, isNull);
    });
  });

  group('search form (SCRUM-68)', () {
    testWidgets('refuses the same place for start and destination', (tester) async {
      final server = _SearchServer();
      final kandy = _town('Kandy');
      await _pump(tester, server.api, SearchTripsScreen(initialFrom: kandy, initialTo: kandy));

      expect(find.text(SearchTripsScreen.samePlaceMessage), findsOneWidget); // shown under the places
      await tester.tap(find.text('Search rides'));
      await tester.pump();
      expect(find.text(SearchTripsScreen.samePlaceMessage), findsNWidgets(2)); // and as a snack bar
      expect(server.queries, isEmpty);
    });

    testWidgets('a custom place with the same coordinates is the same place', (tester) async {
      final server = _SearchServer();
      final kandy = _town('Kandy');
      final pin = TripStop(name: 'Pinned on map', lat: kandy.lat, lng: kandy.lng);
      await _pump(tester, server.api, SearchTripsScreen(initialFrom: pin, initialTo: kandy));

      await tester.tap(find.text('Search rides'));
      await tester.pump();
      expect(server.queries, isEmpty);
      expect(find.text(SearchTripsScreen.samePlaceMessage), findsWidgets);
    });

    testWidgets('a search is saved in recent searches; swap still works', (tester) async {
      final server = _SearchServer();
      final recent = RecentSearches();
      await _pump(
        tester,
        server.api,
        SearchTripsScreen(initialFrom: _town('Colombo Fort'), initialTo: _town('Kandy'), recentSearches: recent),
      );
      expect(find.text('Recent searches'), findsNothing);

      await tester.tap(find.byTooltip('Swap start and destination'));
      await tester.pump();
      await tester.tap(find.text('Search rides'));
      await tester.pumpAndSettle();
      expect(server.last, containsPair('fromLat', '${_town('Kandy').lat}'));

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(recent.items.single.from.name, 'Kandy');
      expect(find.text('Recent searches'), findsOneWidget);
      expect(find.text('Kandy → Colombo Fort'), findsOneWidget);
    });

    testWidgets('tapping a recent search fills the form; a past date is not kept', (tester) async {
      final server = _SearchServer();
      final recent = RecentSearches()
        ..add(SearchQuery(from: _town('Galle'), to: _town('Matara'), date: DateTime(2020, 1, 1), seats: 3));
      await _pump(tester, server.api, SearchTripsScreen(recentSearches: recent));

      await tester.tap(find.text('Galle → Matara'));
      await tester.pump();
      expect(find.text('Galle'), findsOneWidget);
      expect(find.text('Matara'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // seats
      final tomorrow = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Tomorrow'));
      expect(tomorrow.selected, isTrue);

      await tester.tap(find.text('Search rides'));
      await tester.pumpAndSettle();
      final tomorrowDate = DateTime.now().add(const Duration(days: 1));
      expect(server.last, allOf(containsPair('seats', '3'), containsPair('date', isoDate(tomorrowDate))));
    });
  });

  group('results, filters and paging (SCRUM-67, SCRUM-69)', () {
    testWidgets('sorting is sent to the server', (tester) async {
      final server = _SearchServer()..respond = (q) async => _SearchServer.page(q, total: 3);
      await _pump(tester, server.api, SearchResultsScreen(query: _query));
      expect(server.last, allOf(containsPair('sort', 'earliest'), containsPair('page', '1')));
      expect(find.text('3 rides found'), findsOneWidget);

      await _tapChip(tester, 'Cheapest');
      expect(server.last, allOf(containsPair('sort', 'cheapest'), containsPair('page', '1')));
      await _tapChip(tester, 'Closest pickup');
      expect(server.last['sort'], 'closest');
      expect(server.queries, hasLength(3));
    });

    testWidgets('the filter sheet applies and clears filters', (tester) async {
      final server = _SearchServer()..respond = (q) async => _SearchServer.page(q, total: 2);
      await _pump(tester, server.api, SearchResultsScreen(query: _query));

      await tester.tap(find.widgetWithText(ActionChip, 'Filters'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('maxPrice')), '1500');
      await tester.tap(find.text('Takes cargo'));
      await tester.enterText(find.byKey(const Key('minCargo')), '50');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(
        server.last,
        allOf(containsPair('maxPriceCents', '150000'), containsPair('allowsCargo', 'true'),
            containsPair('minCargoKg', '50')),
      );
      expect(find.text('Filters (3)'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, 'Filters (3)'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '1500'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(server.last.keys, isNot(contains('maxPriceCents')));
      expect(server.last.keys, isNot(contains('allowsCargo')));
      expect(find.text('Filters'), findsOneWidget);
    });

    testWidgets('the filter sheet refuses a weight that is not allowed', (tester) async {
      final server = _SearchServer();
      await _pump(tester, server.api, const Scaffold(body: SearchFiltersSheet()));

      await tester.enterText(find.byKey(const Key('minCargo')), '0');
      await tester.tap(find.text('Apply'));
      await tester.pump();
      expect(find.text('Enter a weight between 1 and 2000 kg'), findsOneWidget);
    });

    testWidgets('no results with filters offers Clear filters', (tester) async {
      final server = _SearchServer()
        ..respond = (q) async => _SearchServer.page(q, total: q.containsKey('maxPriceCents') ? 0 : 2);
      await _pump(
        tester,
        server.api,
        SearchResultsScreen(query: _query.copyWith(filters: const SearchFilters(maxPriceCents: 100))),
      );

      expect(find.text('No rides match your filters.'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();

      expect(server.last.keys, isNot(contains('maxPriceCents')));
      expect(find.text('2 rides found'), findsOneWidget);
    });

    testWidgets('no results without filters suggests changing the search', (tester) async {
      final server = _SearchServer();
      await _pump(tester, server.api, SearchResultsScreen(query: _query));

      expect(find.textContaining('No rides found within 5 km'), findsOneWidget);
      expect(find.text('Change search'), findsOneWidget);
      expect(find.text('Clear filters'), findsNothing);
    });

    testWidgets('an error shows a retry button', (tester) async {
      final server = _SearchServer();
      var fail = true;
      server.respond =
          (q) async => fail ? _fail(500, 'INTERNAL_ERROR', 'Server down') : _SearchServer.page(q, total: 1);
      await _pump(tester, server.api, SearchResultsScreen(query: _query));

      expect(find.text('Something went wrong'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('1 ride found'), findsOneWidget);
    });

    testWidgets('loads the next page at the end of the list', (tester) async {
      final server = _SearchServer()..respond = (q) async => _SearchServer.page(q, total: 25);
      await _pump(tester, server.api, SearchResultsScreen(query: _query));
      expect(find.text('25 rides found'), findsOneWidget);
      expect(server.queries, hasLength(1));

      await tester.dragUntilVisible(find.text('Stop 24 → Kandy'), find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(server.queries.map((q) => q['page']), ['1', '2']);
      expect(find.text('Stop 24 → Kandy'), findsOneWidget);
      expect(server.queries.last['sort'], 'earliest'); // the same sort on every page
    });

    testWidgets('a failed page shows a retry row', (tester) async {
      final server = _SearchServer();
      var failPage2 = true;
      server.respond = (q) async =>
          q['page'] == '2' && failPage2 ? _fail(503, 'UNAVAILABLE', 'Try later') : _SearchServer.page(q, total: 25);
      await _pump(tester, server.api, SearchResultsScreen(query: _query));

      await tester.dragUntilVisible(find.text('Retry'), find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('Could not load more rides.'), findsOneWidget);

      failPage2 = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(find.text('Stop 24 → Kandy'), find.byType(ListView), const Offset(0, -400));
      expect(find.text('Could not load more rides.'), findsNothing);
    });

    testWidgets('an old response is ignored when the sort changed while it was loading', (tester) async {
      final server = _SearchServer();
      final slow = Completer<http.Response>();
      server.respond = (q) {
        if (q['sort'] == 'cheapest') {
          return slow.future;
        }
        if (q['sort'] == 'closest') {
          return Future.value(_ok({
            'results': [_result('c', pickup: 'Closest trip')]
          }, meta: {
            'total': 1
          }));
        }
        return Future.value(_SearchServer.page(q, total: 2));
      };
      await _pump(tester, server.api, SearchResultsScreen(query: _query));

      await tester.tap(find.widgetWithText(ChoiceChip, 'Cheapest'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Closest pickup'));
      await tester.pump();
      await tester.pump();
      slow.complete(_ok({
        'results': [_result('x', pickup: 'Cheapest trip')]
      }, meta: {
        'total': 1
      }));
      await tester.pumpAndSettle();

      expect(find.text('Closest trip → Kandy'), findsOneWidget);
      expect(find.text('Cheapest trip → Kandy'), findsNothing);
    });
  });

  group('result card (SCRUM-67, SCRUM-74)', () {
    Future<void> pumpCard(WidgetTester tester, TripSearchResult r, {double width = 400}) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ListView(children: [TripResultCard(result: r, seats: 2, onTap: () {})])),
      ));
    }

    testWidgets('shows seats of seats offered, cargo, times and the price per seat', (tester) async {
      final r = TripSearchResult.fromJson(_result(
        't1',
        seatsAvailable: 2,
        seatsOffered: 3,
        cargo: true,
        cargoKg: 120,
        dropAt: '2026-11-27T02:15:00.000Z',
      ));
      await pumpCard(tester, r);

      expect(find.text('2 of 3 seats left'), findsOneWidget);
      expect(find.text('Cargo up to 120 kg'), findsOneWidget);
      expect(find.text(formatTime(r.pickupTime)), findsOneWidget);
      expect(find.text('→ ${formatTime(r.drop.plannedTime!)}'), findsOneWidget);
      expect(find.text('LKR 1,320'), findsOneWidget);
      expect(find.text('per seat'), findsOneWidget);
      expect(find.text('Total for 2 seats: LKR 2,640'), findsOneWidget);
    });

    testWidgets('falls back to the trip end time and to seats left only', (tester) async {
      final r = TripSearchResult.fromJson(_result('t1', seatsAvailable: 1, newFields: false));
      await pumpCard(tester, r);
      expect(find.text('1 seat left'), findsOneWidget);
      expect(find.textContaining('Cargo'), findsNothing);

      final withEnd = TripSearchResult.fromJson(_result('t2', arrivalAt: '2026-11-27T04:00:00.000Z'));
      await pumpCard(tester, withEnd);
      expect(find.text('trip ends ~${formatTime(withEnd.estimatedArrivalTime!)}'), findsOneWidget);
    });

    testWidgets('fits a 320 px wide screen', (tester) async {
      final r = TripSearchResult.fromJson(_result('t1', cargo: true, cargoKg: 1250.5, price: 12345600));
      await pumpCard(tester, r, width: 320);
      expect(tester.takeException(), isNull);
      expect(find.text('Cargo up to 1250.5 kg'), findsOneWidget);
    });
  });
}
