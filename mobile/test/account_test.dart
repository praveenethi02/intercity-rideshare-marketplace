import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rideshare_mobile/core/api_client.dart';
import 'package:rideshare_mobile/core/auth_service.dart';
import 'package:rideshare_mobile/core/session_store.dart';
import 'package:rideshare_mobile/core/theme/app_theme.dart';
import 'package:rideshare_mobile/features/account/account_screen.dart';
import 'package:rideshare_mobile/features/account/splash_screen.dart';

const _nimal = AppUser(
  id: 'u1',
  firstName: 'Nimal',
  lastName: 'Perera',
  fullName: 'Nimal Perera',
  phone: '+94771234567',
  email: 'nimal@example.com',
  role: 'PASSENGER',
);

class _Saved {
  final String firstName;
  final String lastName;
  final String email;
  const _Saved(this.firstName, this.lastName, this.email);
}

Future<({List<_Saved> saved, List<String> events})> _pump(
  WidgetTester tester, {
  AppUser user = _nimal,
  bool withDriver = true,
  Object? saveError,
}) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final saved = <_Saved>[];
  final events = <String>[];
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: AccountScreen(
      user: user,
      onSaveProfile: ({required firstName, required lastName, required email}) async {
        if (saveError != null) throw saveError;
        saved.add(_Saved(firstName, lastName, email));
      },
      onSignOut: () async => events.add('signed out'),
      onOpenDriver: withDriver ? () => events.add('driver') : null,
    ),
  ));
  return (saved: saved, events: events);
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  group('AppUser', () {
    test('initials come from the first and last name', () {
      expect(_nimal.initials, 'NP');
      const old = AppUser(id: 'u', fullName: 'Kasun', phone: '', role: 'PASSENGER');
      expect(old.initials, 'K');
      const empty = AppUser(id: 'u', fullName: '', phone: '', role: 'PASSENGER');
      expect(empty.initials, '?');
    });

    test('roleLabel names each role', () {
      expect(_nimal.roleLabel, 'Passenger');
      expect(_nimal.copyWith(role: 'DRIVER').roleLabel, 'Driver');
      expect(_nimal.copyWith(role: 'ADMIN').roleLabel, 'Admin');
    });
  });

  group('AccountScreen', () {
    testWidgets('shows who is signed in', (tester) async {
      await _pump(tester);

      expect(find.text('NP'), findsOneWidget);
      expect(find.text('Nimal Perera'), findsOneWidget);
      expect(find.text('Passenger'), findsOneWidget);
      expect(find.text('+94771234567'), findsOneWidget);
      expect(find.text('nimal@example.com'), findsOneWidget);
    });

    testWidgets('a passenger is offered to become a driver, a driver sees the driver profile', (tester) async {
      final result = await _pump(tester);
      await tester.tap(find.text('Become a driver'));
      expect(result.events, ['driver']);

      await _pump(tester, user: _nimal.copyWith(role: 'DRIVER'));
      expect(find.text('Driver profile'), findsOneWidget);
      expect(find.text('Driver'), findsOneWidget);
    });

    testWidgets('admins have no driver link', (tester) async {
      await _pump(tester, user: _nimal.copyWith(role: 'ADMIN'), withDriver: false);
      expect(find.text('Become a driver'), findsNothing);
      expect(find.text('Driver profile'), findsNothing);
    });

    testWidgets('signing out asks first', (tester) async {
      final result = await _pump(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('You are signed in as Nimal Perera.'), findsOneWidget);

      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(result.events, isEmpty);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(result.events, ['signed out']);
    });
  });

  group('Edit profile', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('Edit profile'));
      await tester.pumpAndSettle();
    }

    testWidgets('starts with the current details and saves the changes', (tester) async {
      final result = await _pump(tester);
      await open(tester);

      expect(find.widgetWithText(TextFormField, 'Nimal'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Perera'), findsOneWidget);

      await tester.enterText(_field('Nimal'), '  Kasun ');
      await tester.enterText(_field('nimal@example.com'), '');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(result.saved.single.firstName, 'Kasun');
      expect(result.saved.single.lastName, 'Perera');
      expect(result.saved.single.email, '');
      expect(find.text('Edit profile'), findsOneWidget, reason: 'back on the Account tab');
      expect(find.text('Profile updated'), findsOneWidget);
    });

    testWidgets('the mobile number cannot be edited', (tester) async {
      await _pump(tester);
      await open(tester);

      final phone = tester.widget<TextFormField>(_field('+94771234567'));
      expect(phone.enabled, isFalse);
    });

    testWidgets('checks the names and the email before saving', (tester) async {
      final result = await _pump(tester);
      await open(tester);

      await tester.enterText(_field('Perera'), ' ');
      await tester.enterText(_field('nimal@example.com'), 'not-an-email');
      await tester.tap(find.text('Save changes'));
      await tester.pump();

      expect(find.text('Enter your last name'), findsOneWidget);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(result.saved, isEmpty);
    });

    testWidgets('shows the server error and stays on the screen', (tester) async {
      await _pump(tester, saveError: const ApiException(409, 'This email is already used'));
      await open(tester);

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('This email is already used'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
    });
  });

  test('AuthService.updateProfile sends PATCH /users/me and keeps the new user', () async {
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'user': {
                'id': 'u1',
                'firstName': 'Nimal',
                'lastName': 'Perera',
                'fullName': 'Nimal Perera',
                'phone': '+94771234567',
                'role': 'PASSENGER'
              },
              'tokens': {'accessToken': 'a', 'refreshToken': 'r'},
            },
          }),
          200,
        );
      }
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/v1/users/me');
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'user': {
              'id': 'u1',
              'firstName': 'Kasun',
              'lastName': 'Perera',
              'fullName': 'Kasun Perera',
              'phone': '+94771234567',
              'role': 'PASSENGER'
            },
          },
        }),
        200,
      );
    });
    final auth = AuthService('http://test/api/v1', httpClient: client, store: MemorySessionStore());
    await auth.login('0771234567', 'Abcd1234');

    final user = await auth.updateProfile(firstName: 'Kasun', lastName: 'Perera', email: '');

    expect(sent, {'firstName': 'Kasun', 'lastName': 'Perera', 'email': null});
    expect(user.greetingName, 'Kasun');
    expect(auth.user?.fullName, 'Kasun Perera');
  });

  testWidgets('SplashScreen shows the app name while it loads', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const SplashScreen()));
    expect(find.text('Ride Share'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
