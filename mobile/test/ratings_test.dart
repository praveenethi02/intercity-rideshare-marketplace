import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rideshare_mobile/core/api_client.dart';
import 'package:rideshare_mobile/core/theme/app_theme.dart';
import 'package:rideshare_mobile/features/ratings/ratings.dart';

const _pending = {
  'trip': {
    'id': 't1',
    'originName': 'Colombo Fort',
    'destinationName': 'Kandy',
    'departureAt': '2026-11-20T01:30:00.000Z',
    'completedAt': '2026-11-20T05:10:00.000Z',
  },
  'ratee': {'id': 'd1', 'name': 'Kamal P.', 'role': 'DRIVER'},
};

http.Response _json(int status, Object? data, {String message = 'OK', Map<String, Object?>? meta}) => http.Response(
      jsonEncode({'success': status < 400, 'message': message, 'data': data, 'meta': meta}),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class _Server {
  Map<String, dynamic>? sent;
  bool rejectRating = false;
  Map<String, Object?> received = {'averageRating': null, 'ratingCount': 0, 'ratings': <Object>[]};

  RatingApi get api => RatingApi(ApiClient(
        baseUrl: 'http://test/api/v1',
        tokenProvider: () async => 't',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/ratings/pending')) {
            return _json(200, {
              'pending': [if (sent == null || rejectRating) _pending],
            });
          }
          if (request.method == 'POST') {
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            return rejectRating
                ? _json(409, null, message: 'You have already rated this person', meta: {'code': 'ALREADY_RATED'})
                : _json(201, {'rating': <String, Object?>{}});
          }
          return _json(200, received);
        }),
      ));
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester, _Server server) async {
  await _pump(tester, PendingRatingsScreen(api: server.api));
  await tester.tap(find.text('Kamal P.'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sends the stars and review, then the person leaves the list', (tester) async {
    final server = _Server();
    await _openSheet(tester, server);

    await tester.tap(find.byTooltip('4 stars'));
    await tester.enterText(find.byType(TextField), '  Safe driving  ');
    await tester.tap(find.text('Submit rating'));
    await tester.pumpAndSettle();

    expect(server.sent, {'tripId': 't1', 'rateeId': 'd1', 'stars': 4, 'review': 'Safe driving'});
    expect(find.text('Thanks for your rating'), findsOneWidget);
    expect(find.text('No trips to rate.'), findsOneWidget);
  });

  testWidgets('leaves out an empty review', (tester) async {
    final server = _Server();
    await _openSheet(tester, server);
    await tester.tap(find.byTooltip('5 stars'));
    await tester.tap(find.text('Submit rating'));
    await tester.pumpAndSettle();
    expect(server.sent, {'tripId': 't1', 'rateeId': 'd1', 'stars': 5});
  });

  testWidgets('asks for stars before sending', (tester) async {
    final server = _Server();
    await _openSheet(tester, server);
    await tester.tap(find.text('Submit rating'));
    await tester.pumpAndSettle();
    expect(find.text('Choose 1 to 5 stars'), findsOneWidget);
    expect(server.sent, isNull);
  });

  testWidgets('limits the review to 500 characters', (tester) async {
    final server = _Server();
    await _openSheet(tester, server);
    await tester.enterText(find.byType(TextField), 'x' * 600);
    await tester.tap(find.byTooltip('3 stars'));
    await tester.tap(find.text('Submit rating'));
    await tester.pumpAndSettle();
    expect((server.sent!['review'] as String).length, 500);
  });

  testWidgets('shows a server error and keeps the sheet open', (tester) async {
    final server = _Server()..rejectRating = true;
    await _openSheet(tester, server);
    await tester.tap(find.byTooltip('1 star'));
    await tester.tap(find.text('Submit rating'));
    await tester.pumpAndSettle();
    expect(find.text('You have already rated this person'), findsOneWidget);
    expect(find.text('Submit rating'), findsOneWidget);
  });

  testWidgets('received ratings show the average, count and review', (tester) async {
    final server = _Server()
      ..received = {
        'averageRating': 4.67,
        'ratingCount': 3,
        'ratings': [
          {
            'stars': 5,
            'review': 'On time.',
            'createdAt': '2026-11-21T14:05:00.000Z',
            'reviewer': {'id': 'p1', 'name': 'Nimal S.'},
          },
        ],
      };
    await _pump(tester, ReceivedRatingsScreen(api: server.api, userId: 'u1'));
    expect(find.text('4.7'), findsOneWidget);
    expect(find.text('3 ratings'), findsOneWidget);
    expect(find.text('On time.'), findsOneWidget);
  });

  testWidgets('received ratings can be empty', (tester) async {
    await _pump(tester, ReceivedRatingsScreen(api: _Server().api, userId: 'u1'));
    expect(find.text('No ratings yet.'), findsOneWidget);
  });
}