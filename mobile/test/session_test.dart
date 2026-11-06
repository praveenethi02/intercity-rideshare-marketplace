import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rideshare_mobile/core/api_client.dart';
import 'package:rideshare_mobile/core/auth_service.dart';
import 'package:rideshare_mobile/core/session_store.dart';
import 'package:rideshare_mobile/main.dart';

const _url = 'http://api.test/api/v1';
const _user = {'id': 'u1', 'fullName': 'Nimal Silva', 'phone': '+94771234567', 'role': 'PASSENGER'};

Map<String, String> _tokens(String refresh) => {'accessToken': 'access-$refresh', 'refreshToken': refresh};

http.Response _ok(Map<String, Object?> data) =>
    http.Response(jsonEncode({'success': true, 'message': 'OK', 'data': data, 'meta': {}}), 200);

http.Response _fail(int status, [String code = 'FAILED']) => http.Response(
      jsonEncode({'success': false, 'message': 'Failed $code', 'meta': {'code': code}}),
      status,
    );

/// Answers requests by path and records them. Throwing from [handler] acts like no connection.
class _Api {
  _Api(this.handler);
  http.Response Function(String path) handler;
  final paths = <String>[];

  late final client = MockClient((request) async {
    final path = request.url.path.replaceFirst('/api/v1', '');
    paths.add(path);
    return handler(path);
  });

  int count(String path) => paths.where((p) => p == path).length;
}

void main() {
  group('AuthService', () {
    test('signing in saves the refresh token and API address', () async {
      final store = MemorySessionStore();
      final api = _Api((_) => _ok({'user': _user, 'tokens': _tokens('r1')}));

      await AuthService(_url, httpClient: api.client, store: store).login('0771234567', 'Abcd1234');

      expect(store.refreshToken, 'r1');
      expect(store.baseUrl, _url);
    });

    test('a refresh saves the new token, because the old one no longer works', () async {
      final store = MemorySessionStore();
      final api = _Api((path) => path == '/auth/refresh'
          ? _ok({'tokens': _tokens('r2')})
          : _ok({'user': _user, 'tokens': _tokens('r1')}));
      final auth = AuthService(_url, httpClient: api.client, store: store);
      await auth.login('0771234567', 'Abcd1234');

      expect(await auth.refresh(), isTrue);

      expect(store.refreshToken, 'r2');
    });

    test('requests that need a refresh at the same time share one', () async {
      final api = _Api((path) => path == '/auth/refresh'
          ? _ok({'tokens': _tokens('r2')})
          : _ok({'user': _user, 'tokens': _tokens('r1')}));
      final auth = AuthService(_url, httpClient: api.client);
      await auth.login('0771234567', 'Abcd1234');

      final results = await Future.wait([auth.refresh(), auth.refresh(), auth.refresh()]);

      expect(results, [true, true, true]);
      expect(api.count('/auth/refresh'), 1);
    });

    test('losing the connection during a refresh keeps the saved token', () async {
      final store = MemorySessionStore();
      final api = _Api((path) => path == '/auth/refresh'
          ? throw http.ClientException('offline')
          : _ok({'user': _user, 'tokens': _tokens('r1')}));
      final auth = AuthService(_url, httpClient: api.client, store: store);
      await auth.login('0771234567', 'Abcd1234');

      expect(await auth.refresh(), isFalse);
      expect(store.refreshToken, 'r1');

      // The same token still works once the connection is back.
      api.handler = (_) => _ok({'tokens': _tokens('r2')});
      expect(await auth.refresh(), isTrue);
      expect(store.refreshToken, 'r2');
    });

    test('a rate limit or server error keeps the saved token', () async {
      for (final status in [429, 500, 503]) {
        final store = MemorySessionStore();
        final api = _Api((path) => path == '/auth/refresh'
            ? _fail(status)
            : _ok({'user': _user, 'tokens': _tokens('r1')}));
        final auth = AuthService(_url, httpClient: api.client, store: store);
        await auth.login('0771234567', 'Abcd1234');

        expect(await auth.refresh(), isFalse);
        expect(store.refreshToken, 'r1', reason: '$status');
      }
    });

    test('a rejected refresh token is forgotten', () async {
      final store = MemorySessionStore();
      final api = _Api((path) => path == '/auth/refresh'
          ? _fail(401, 'INVALID_REFRESH_TOKEN')
          : _ok({'user': _user, 'tokens': _tokens('r1')}));
      final auth = AuthService(_url, httpClient: api.client, store: store);
      await auth.login('0771234567', 'Abcd1234');

      expect(await auth.refresh(), isFalse);

      expect(store.refreshToken, isNull);
      expect(store.baseUrl, _url);
    });

    test('signing out forgets the token even when the server cannot be reached', () async {
      final store = MemorySessionStore();
      final api = _Api((path) => path == '/auth/logout'
          ? throw http.ClientException('offline')
          : _ok({'user': _user, 'tokens': _tokens('r1')}));
      final auth = AuthService(_url, httpClient: api.client, store: store);
      await auth.login('0771234567', 'Abcd1234');

      await auth.logout();

      expect(store.refreshToken, isNull);
      expect(store.baseUrl, _url);
      expect(auth.user, isNull);
    });

    test('restore loads the current user with a new token', () async {
      final store = MemorySessionStore(baseUrl: _url, refreshToken: 'r1');
      final api = _Api((path) => path == '/auth/refresh' ? _ok({'tokens': _tokens('r2')}) : _ok({'user': _user}));
      final auth = AuthService(_url, httpClient: api.client, store: store);

      final user = await auth.restore('r1');

      expect(user.fullName, 'Nimal Silva');
      expect(store.refreshToken, 'r2');
    });

    test('restore forgets the token when the account can no longer be used', () async {
      final store = MemorySessionStore(baseUrl: _url, refreshToken: 'r1');
      final api = _Api((path) => path == '/auth/refresh' ? _ok({'tokens': _tokens('r2')}) : _fail(403, 'ACCOUNT_SUSPENDED'));
      final auth = AuthService(_url, httpClient: api.client, store: store);

      await expectLater(auth.restore('r1'), throwsA(isA<ApiException>()));

      expect(store.refreshToken, isNull);
    });
  });

  group('app start', () {
    http.Response Function(String) working() => (path) {
          if (path == '/auth/refresh') return _ok({'tokens': _tokens('r2')});
          if (path == '/users/me') return _ok({'user': _user});
          return _fail(404);
        };

    Future<void> pumpApp(WidgetTester tester, SessionStore store, _Api api) async {
      await tester.pumpWidget(RideshareApp(store: store, httpClient: api.client));
      await tester.pumpAndSettle();
    }

    testWidgets('with no saved session it shows sign in and calls nothing', (tester) async {
      final api = _Api(working());
      await pumpApp(tester, MemorySessionStore(), api);

      expect(find.text('Sign in'), findsWidgets);
      expect(api.paths, isEmpty);
    });

    testWidgets('sign in uses the last API address after the session has ended', (tester) async {
      final api = _Api(working());
      await pumpApp(tester, MemorySessionStore(baseUrl: 'http://192.168.1.5:4000/api/v1'), api);

      await tester.tap(find.text('Developer settings'));
      await tester.pumpAndSettle();

      expect(find.text('http://192.168.1.5:4000/api/v1'), findsOneWidget);
    });

    testWidgets('with a saved session it shows a spinner, then opens home', (tester) async {
      final api = _Api(working());
      final store = MemorySessionStore(baseUrl: _url, refreshToken: 'r1');

      await tester.pumpWidget(RideshareApp(store: store, httpClient: api.client));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Mobile number'), findsNothing);

      await tester.pumpAndSettle();

      expect(find.text('Find a ride'), findsWidgets);
      expect(find.text('Mobile number'), findsNothing);
      expect(store.refreshToken, 'r2');
    });

    testWidgets('an expired session goes to sign in and forgets the token', (tester) async {
      final api = _Api((_) => _fail(401, 'INVALID_REFRESH_TOKEN'));
      final store = MemorySessionStore(baseUrl: _url, refreshToken: 'r1');
      await pumpApp(tester, store, api);

      expect(find.text('Mobile number'), findsOneWidget);
      expect(store.refreshToken, isNull);
    });

    testWidgets('with no connection it keeps the session and offers to try again', (tester) async {
      final api = _Api((_) => throw http.ClientException('offline'));
      final store = MemorySessionStore(baseUrl: _url, refreshToken: 'r1');
      await pumpApp(tester, store, api);

      expect(find.textContaining('Cannot reach the server'), findsOneWidget);
      expect(find.text('Mobile number'), findsNothing);
      expect(store.refreshToken, 'r1');

      api.handler = working();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Find a ride'), findsWidgets);
    });

    testWidgets('the user can leave the retry screen and use another account', (tester) async {
      final api = _Api((_) => throw http.ClientException('offline'));
      final store = MemorySessionStore(baseUrl: _url, refreshToken: 'r1');
      await pumpApp(tester, store, api);

      await tester.tap(find.text('Sign in with another account'));
      await tester.pumpAndSettle();

      expect(find.text('Mobile number'), findsOneWidget);
      expect(store.refreshToken, isNull);
    });
  });
}
