import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rideshare_mobile/core/auth_service.dart';
import 'package:rideshare_mobile/features/auth/auth.dart';
import 'package:rideshare_mobile/features/auth/widgets/auth_widgets.dart';

const _user = {'id': 'u1', 'fullName': 'Nimal Silva', 'phone': '+94771234567', 'role': 'PASSENGER'};
const _tokens = {'accessToken': 'access', 'refreshToken': 'refresh'};

http.Response _ok([Map<String, Object?>? data]) => http.Response(
      jsonEncode({'success': true, 'message': 'OK', 'data': data, 'meta': {}}),
      200,
    );

http.Response _fail(int status, String code, String message, [List<Map<String, String>>? details]) => http.Response(
      jsonEncode({
        'success': false,
        'message': message,
        'meta': {'code': code, if (details != null) 'details': details},
      }),
      status,
    );

/// Records each request as "path" and its JSON body, then answers with [handler].
class _Api {
  _Api(this.handler);
  final http.Response Function(String path) handler;
  final calls = <String, Map<String, dynamic>>{};

  late final client = MockClient((request) async {
    final path = request.url.path.replaceFirst('/api/v1', '');
    calls[path] = jsonDecode(request.body) as Map<String, dynamic>;
    return handler(path);
  });
}

/// Pumps the login screen and returns the list that collects signed-in services.
Future<List<AuthService>> _pumpLogin(WidgetTester tester, _Api api) async {
  // Tall enough that every field is on screen.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final signedIn = <AuthService>[];
  await tester.pumpWidget(MaterialApp(home: LoginScreen(onSignedIn: signedIn.add, httpClient: api.client)));
  return signedIn;
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

/// Removes the screen so the resend countdown stops before the test ends.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  group('validators', () {
    test('phone accepts the formats the backend accepts', () {
      for (final phone in ['0771234567', '94771234567', '+94771234567', '077 123-4567']) {
        expect(validatePhone(phone), isNull, reason: phone);
      }
      for (final phone in ['', '077123456', '0671234567', '+15551234567']) {
        expect(validatePhone(phone), isNotNull, reason: phone);
      }
    });

    test('new password needs 8 characters, a letter and a number', () {
      expect(validateNewPassword('Abcd1234'), isNull);
      expect(validateNewPassword('Abc123'), isNotNull);
      expect(validateNewPassword('abcdefgh'), isNotNull);
      expect(validateNewPassword('12345678'), isNotNull);
      expect(validateNewPassword('a1${'x' * 71}'), isNotNull);
    });

    test('code must be 6 digits', () {
      expect(validateOtp('123456'), isNull);
      expect(validateOtp('12345'), isNotNull);
      expect(validateOtp('12345a'), isNotNull);
    });
  });

  group('sign in', () {
    testWidgets('signs in and sends the entered details', (tester) async {
      final api = _Api((_) => _ok({'user': _user, 'tokens': _tokens}));
      final signedIn = await _pumpLogin(tester, api);

      await tester.enterText(_field('Mobile number'), '0771234567');
      await tester.enterText(_field('Password'), 'Abcd1234');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(api.calls['/auth/login'], {'phone': '0771234567', 'password': 'Abcd1234'});
      expect(signedIn.single.user?.fullName, 'Nimal Silva');
    });

    testWidgets('shows the server message for a wrong password', (tester) async {
      final api = _Api((_) => _fail(401, 'INVALID_CREDENTIALS', 'Incorrect phone number or password'));
      final signedIn = await _pumpLogin(tester, api);

      await tester.enterText(_field('Mobile number'), '0771234567');
      await tester.enterText(_field('Password'), 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect phone number or password'), findsOneWidget);
      expect(signedIn, isEmpty);
    });

    testWidgets('does not call the API when the form is invalid', (tester) async {
      final api = _Api((_) => _ok());
      await _pumpLogin(tester, api);

      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(find.textContaining('valid mobile number'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('an unverified account is sent a code and asked for it', (tester) async {
      final api = _Api((path) => switch (path) {
            '/auth/login' => _fail(403, 'PHONE_NOT_VERIFIED', 'Verify your phone number first'),
            _ => _ok(),
          });
      await _pumpLogin(tester, api);

      await tester.enterText(_field('Mobile number'), '0771234567');
      await tester.enterText(_field('Password'), 'Abcd1234');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(api.calls['/auth/otp/resend'], {'phone': '0771234567'});
      expect(find.text('Enter the code'), findsOneWidget);
      await _finish(tester);
    });
  });

  group('registration', () {
    Future<void> openAndFill(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(OutlinedButton, 'Create an account'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Full name'), 'Nimal Silva');
      await tester.enterText(_field('Mobile number'), '0771234567');
      await tester.enterText(_field('Password'), 'Abcd1234');
      await tester.enterText(_field('Confirm password'), 'Abcd1234');
    }

    testWidgets('registers, verifies the code and signs in', (tester) async {
      final api = _Api((path) => path == '/auth/otp/verify' ? _ok({'user': _user, 'tokens': _tokens}) : _ok({'user': _user}));
      final signedIn = await _pumpLogin(tester, api);

      await openAndFill(tester);
      await tester.tap(find.text('Driver'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // The optional email is left out, as the backend rejects an empty one.
      expect(api.calls['/auth/register'], {
        'fullName': 'Nimal Silva',
        'phone': '0771234567',
        'password': 'Abcd1234',
        'role': 'DRIVER',
      });
      expect(find.text('Enter the code'), findsOneWidget);
      expect(find.textContaining('Send a new code in'), findsOneWidget);

      await tester.enterText(_field('Code'), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(api.calls['/auth/otp/verify'], {'phone': '0771234567', 'otp': '123456'});
      expect(signedIn.single.user?.id, 'u1');
      await _finish(tester);
    });

    testWidgets('rejects passwords that do not match', (tester) async {
      final api = _Api((_) => _ok());
      await _pumpLogin(tester, api);

      await openAndFill(tester);
      await tester.enterText(_field('Confirm password'), 'Different1');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();

      expect(find.text('The passwords do not match'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('shows when the phone is already registered', (tester) async {
      final api = _Api((_) => _fail(409, 'PHONE_ALREADY_REGISTERED', 'This phone number is already registered'));
      await _pumpLogin(tester, api);

      await openAndFill(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(find.text('This phone number is already registered'), findsOneWidget);
      expect(find.text('Enter the code'), findsNothing);
    });

    testWidgets('shows validation messages from the server', (tester) async {
      final api = _Api((_) => _fail(400, 'VALIDATION_ERROR', 'Validation failed', [
            {'field': 'phone', 'message': 'Enter a valid Sri Lankan mobile number'},
          ]));
      await _pumpLogin(tester, api);

      await openAndFill(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid Sri Lankan mobile number'), findsOneWidget);
    });

    testWidgets('a wrong code keeps the user on the code screen', (tester) async {
      final api = _Api((path) => path == '/auth/otp/verify'
          ? _fail(400, 'OTP_INVALID_OR_EXPIRED', 'The code is incorrect or has expired')
          : _ok({'user': _user}));
      final signedIn = await _pumpLogin(tester, api);

      await openAndFill(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(_field('Code'), '000000');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await tester.pump();
      await tester.pump();

      expect(find.text('The code is incorrect or has expired'), findsOneWidget);
      expect(signedIn, isEmpty);
      await _finish(tester);
    });

    testWidgets('a new code can be requested after the countdown', (tester) async {
      final api = _Api((_) => _ok({'user': _user}));
      await _pumpLogin(tester, api);

      await openAndFill(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.textContaining('Send a new code in'), warnIfMissed: false);
      await tester.pump();
      expect(api.calls.containsKey('/auth/otp/resend'), isFalse);

      await tester.pump(const Duration(seconds: 60));
      await tester.tap(find.text('Send a new code'));
      await tester.pump();
      await tester.pump();

      expect(api.calls['/auth/otp/resend'], {'phone': '0771234567'});
      expect(find.text('Send a new code in 60s'), findsOneWidget);
      await _finish(tester);
    });
  });

  group('forgotten password', () {
    testWidgets('sends a code, resets the password and returns to sign in', (tester) async {
      final api = _Api((_) => _ok());
      await _pumpLogin(tester, api);

      await tester.enterText(_field('Mobile number'), '0771234567');
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      // The number already entered is carried over.
      await tester.tap(find.widgetWithText(FilledButton, 'Send code'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(api.calls['/auth/password/forgot'], {'phone': '0771234567'});

      await tester.enterText(_field('Code'), '123456');
      await tester.enterText(_field('New password'), 'Newpass123');
      await tester.enterText(_field('Confirm new password'), 'Newpass123');
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(api.calls['/auth/password/reset'], {'phone': '0771234567', 'otp': '123456', 'newPassword': 'Newpass123'});
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      expect(find.textContaining('Password changed'), findsOneWidget);
    });
  });
}
