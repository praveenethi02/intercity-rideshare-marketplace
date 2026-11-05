import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rideshare_mobile/core/api_client.dart';
import 'package:rideshare_mobile/features/driver/driver.dart';
import 'package:rideshare_mobile/features/driver/widgets/driver_widgets.dart';

http.Response _ok(Object data, {Object? meta}) => http.Response(
      jsonEncode({'success': true, 'message': 'OK', 'data': data, 'meta': meta}),
      200,
    );

http.Response _fail(int status, String code, String message) => http.Response(
      jsonEncode({'success': false, 'message': message, 'data': null, 'meta': {'code': code}}),
      status,
    );

Map<String, dynamic> _document(String type) => {
      'id': 'doc-$type',
      'type': type,
      'url': 'http://localhost:4000/api/v1/files/abc.png?expires=1&sig=x',
      'uploadedAt': '2026-11-05T10:00:00.000Z',
    };

Map<String, dynamic> _driver({
  String verification = 'PENDING',
  String accountStatus = 'ACTIVE',
  String? rejectionReason,
  List<String> documents = const [],
}) =>
    {
      'id': 'user-1',
      'userId': 'user-1',
      'licenceNumber': 'B1234567',
      'licenceExpiry': '2099-01-31',
      'dateOfBirth': '1995-03-10',
      'address': '12 Kandy Road',
      'emergencyContactName': 'Kamal Silva',
      'emergencyContactPhone': '+94771234567',
      'verification': verification,
      'rejectionReason': rejectionReason,
      'verifiedAt': null,
      'accountStatus': accountStatus,
      'averageRating': 4.5,
      'ratingCount': 2,
      'completedTrips': 3,
      'documents': documents.map(_document).toList(),
    };

DriverRepository _repository(MockClientHandler handler, {String baseUrl = 'http://10.0.2.2:4000/api/v1'}) =>
    DriverRepository(ApiClient(
      baseUrl: baseUrl,
      tokenProvider: () async => 'token',
      httpClient: MockClient(handler),
    ));

Future<void> _show(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('DriverRepository', () {
    test('returns null when the user is not a driver yet', () async {
      final repository = _repository((_) async => _fail(403, 'FORBIDDEN', 'Only drivers can do this'));
      expect(await repository.myProfile(), isNull);
    });

    test('keeps other 403 errors, such as a closed account', () async {
      final repository = _repository((_) async => _fail(403, 'ACCOUNT_NOT_ACTIVE', 'This account is not active'));
      expect(repository.myProfile(), throwsA(isA<ApiException>()));
    });

    test('reads a profile and points file links at the address the app uses', () async {
      final repository = _repository((_) async => _ok({'driver': _driver(documents: ['NIC_FRONT'])}));

      final driver = (await repository.myProfile())!;

      expect(driver.licenceNumber, 'B1234567');
      expect(driver.averageRating, 4.5);
      expect(driver.documents.single.url, startsWith('http://10.0.2.2:4000/api/v1/files/abc.png?'));
    });

    test('uploads a document as multipart with its type', () async {
      late http.Request sent;
      final repository = _repository((request) async {
        sent = request;
        return _ok({'document': _document('NIC_BACK')});
      });

      final document = await repository.uploadDocument('NIC_BACK', [1, 2, 3], 'nic.png');

      expect(sent.url.path, '/api/v1/drivers/me/documents');
      expect(sent.headers['content-type'], startsWith('multipart/form-data'));
      expect(sent.headers['Authorization'], 'Bearer token');
      expect(sent.body, contains('name="type"'));
      expect(sent.body, contains('NIC_BACK'));
      expect(sent.body, contains('filename="nic.png"'));
      expect(document.type, 'NIC_BACK');
    });

    test('sends trip filters and reads paging', () async {
      late Uri asked;
      final repository = _repository((request) async {
        asked = request.url;
        return _ok(
          {
            'trips': [
              {'id': 't1', 'originName': 'Kandy', 'destinationName': 'Colombo', 'status': 'COMPLETED'},
            ],
          },
          meta: {'page': 1, 'limit': 20, 'total': 21, 'totalPages': 2},
        );
      });

      final page = await repository.trips(status: 'COMPLETED');

      expect(asked.queryParameters, {'status': 'COMPLETED', 'page': '1', 'limit': '20'});
      expect(page.trips.single.destinationName, 'Colombo');
      expect(page.hasMore, isTrue);
    });
  });

  group('DriverValidators', () {
    test('match the backend rules', () {
      expect(DriverValidators.licence('B1234567'), isNull);
      expect(DriverValidators.licence('!'), isNotNull);
      expect(DriverValidators.nic('199912345678'), isNull);
      expect(DriverValidators.nic('991234567V'), isNull);
      expect(DriverValidators.nic('12345'), isNotNull);
      expect(DriverValidators.phone('077 123 4567'), isNull);
      expect(DriverValidators.phone('+94771234567'), isNull);
      expect(DriverValidators.phone('0112345678'), isNotNull);
    });

    test('work out the 18th birthday cut-off, including leap days', () {
      expect(DriverValidators.latestAdultBirthDate(DateTime(2026, 11, 5)), DateTime(2008, 11, 5));
      expect(DriverValidators.latestAdultBirthDate(DateTime(2024, 2, 29)), DateTime(2006, 2, 28));
    });
  });

  group('DriverHomeScreen', () {
    testWidgets('invites a non-driver to register', (tester) async {
      final repository = _repository((_) async => _fail(403, 'FORBIDDEN', 'Only drivers can do this'));

      await _show(tester, DriverHomeScreen(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Become a driver'), findsOneWidget);
    });

    testWidgets('shows how many documents are left', (tester) async {
      final repository = _repository((_) async => _ok({'driver': _driver(documents: ['NIC_FRONT'])}));

      await _show(tester, DriverHomeScreen(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Upload 4 more documents to send your application for review.'), findsOneWidget);
      expect(find.text('1 of 5 uploaded'), findsOneWidget);
      expect(find.text('Documents needed'), findsOneWidget);
      expect(find.text('In review'), findsNothing);
    });

    testWidgets('shows in review once every document is uploaded', (tester) async {
      final repository = _repository((_) async => _ok({'driver': _driver(documents: driverDocumentTypes)}));

      await _show(tester, DriverHomeScreen(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('In review'), findsOneWidget);
      expect(find.text('An admin is reviewing your documents.'), findsOneWidget);
    });

    testWidgets('shows the reason for a rejection', (tester) async {
      final repository = _repository(
        (_) async => _ok({'driver': _driver(verification: 'REJECTED', rejectionReason: 'Blurry licence')}),
      );

      await _show(tester, DriverHomeScreen(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Reason from the admin: Blurry licence'), findsOneWidget);
    });

    testWidgets('a suspended account shows suspended rather than approved', (tester) async {
      final repository = _repository(
        (_) async => _ok({'driver': _driver(verification: 'APPROVED', accountStatus: 'SUSPENDED')}),
      );

      await _show(tester, DriverHomeScreen(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Suspended'), findsOneWidget);
      expect(find.text('Approved'), findsNothing);
    });
  });

  group('BecomeDriverScreen', () {
    testWidgets('checks the form before sending anything', (tester) async {
      var requests = 0;
      final repository = _repository((_) async {
        requests += 1;
        return _ok({});
      });

      await _show(tester, BecomeDriverScreen(repository: repository));
      await tester.tap(find.text('Register as a driver'));
      await tester.pump();

      expect(requests, 0);
      expect(find.text('Choose the expiry date'), findsOneWidget);
      expect(find.text('Choose your date of birth'), findsOneWidget);
      expect(find.text('Enter 9 digits and V or X, or 12 digits'), findsOneWidget);
    });
  });

  group('DriverDocumentsScreen', () {
    testWidgets('lists all five documents and uploads the chosen file', (tester) async {
      final uploaded = <String>['LICENCE_FRONT'];
      String? sentBody;
      final repository = _repository((request) async {
        if (request.method == 'POST') {
          sentBody = request.body;
          uploaded.add('NIC_FRONT');
          return _ok({'document': _document('NIC_FRONT')});
        }
        return _ok({'driver': _driver(documents: uploaded)});
      });

      await _show(
        tester,
        DriverDocumentsScreen(
          repository: repository,
          pickFile: () async => const PickedDocument([1, 2, 3], 'nic.png'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      for (final type in driverDocumentTypes) {
        expect(find.text(driverDocumentLabel(type)), findsOneWidget);
      }
      expect(find.text('1 of 5 uploaded'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
      expect(find.text('Upload'), findsNWidgets(4));

      final nicCard = find.ancestor(of: find.text('NIC (front)'), matching: find.byType(Card));
      await tester.tap(find.descendant(of: nicCard, matching: find.text('Upload')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(sentBody, contains('NIC_FRONT'));
      expect(find.text('2 of 5 uploaded'), findsOneWidget);
    });

    testWidgets('refuses a file over 5 MB without sending it', (tester) async {
      var uploads = 0;
      final repository = _repository((request) async {
        if (request.method == 'POST') uploads += 1;
        return _ok({'driver': _driver()});
      });

      await _show(
        tester,
        DriverDocumentsScreen(
          repository: repository,
          pickFile: () async => PickedDocument(List.filled(5 * 1024 * 1024 + 1, 0), 'big.png'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Upload').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(uploads, 0);
      expect(find.text('That file is over 5 MB. Choose a smaller one.'), findsOneWidget);
    });

    testWidgets('warns an approved driver before replacing an identity document', (tester) async {
      final repository = _repository(
        (_) async => _ok({'driver': _driver(verification: 'APPROVED', documents: driverDocumentTypes)}),
      );
      var picks = 0;

      await _show(
        tester,
        DriverDocumentsScreen(
          repository: repository,
          pickFile: () async {
            picks += 1;
            return null;
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Replace').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Replace this document?'), findsOneWidget);
      expect(picks, 0);

      await tester.tap(find.text('No'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(picks, 0);
    });
  });

  group('DriverVerificationScreen', () {
    testWidgets('lists the documents still needed', (tester) async {
      final repository = _repository((_) async => _ok({
            'verification': {
              'id': null,
              'status': 'PENDING',
              'reason': null,
              'missingDocuments': ['NIC_BACK', 'PROFILE_PHOTO'],
              'documents': [],
              'submittedAt': null,
              'decidedAt': null,
            },
          }));

      await _show(tester, DriverVerificationScreen(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('NIC (back)'), findsOneWidget);
      expect(find.text('Profile photo'), findsOneWidget);
    });
  });

  group('DriverProfileScreen', () {
    testWidgets('sends only what changed and needs no review for contact details', (tester) async {
      Map<String, dynamic>? sent;
      final repository = _repository((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _ok({'driver': _driver(verification: 'APPROVED')..['address'] = 'New address'});
      });
      final driver = DriverProfile.fromJson(_driver(verification: 'APPROVED'));

      await _show(tester, DriverProfileScreen(repository: repository, driver: driver));
      await tester.enterText(find.widgetWithText(TextFormField, 'Address'), 'New address');
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(sent, {'address': 'New address'});
      expect(find.text('Change your licence details?'), findsNothing);
      expect(find.text('Profile saved'), findsOneWidget);
    });

    testWidgets('warns before a licence change sends an approved driver back to review', (tester) async {
      var requests = 0;
      final repository = _repository((_) async {
        requests += 1;
        return _ok({'driver': _driver()});
      });
      final driver = DriverProfile.fromJson(_driver(verification: 'APPROVED'));

      await _show(tester, DriverProfileScreen(repository: repository, driver: driver));
      await tester.enterText(find.widgetWithText(TextFormField, 'Licence number'), 'B7654321');
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Change your licence details?'), findsOneWidget);
      expect(requests, 0);
    });
  });

  group('DriverEarningsScreen and DriverTripHistoryScreen', () {
    testWidgets('earnings show the summary', (tester) async {
      final repository = _repository((_) async => _ok({
            'earnings': {
              'currency': 'LKR',
              'seatEarnings': 0,
              'cargoEarnings': 0,
              'platformFees': 0,
              'paidOut': 0,
              'pendingPayout': 0,
              'completedTrips': 3,
            },
          }));

      await _show(tester, DriverEarningsScreen(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Seat earnings'), findsOneWidget);
      expect(find.text('Completed trips'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('trip history filters by status', (tester) async {
      final asked = <String?>[];
      final repository = _repository((request) async {
        final status = request.url.queryParameters['status'];
        asked.add(status);
        return _ok(
          {
            'trips': status == 'CANCELLED'
                ? []
                : [
                    {'id': 't1', 'originName': 'Kandy', 'destinationName': 'Colombo', 'status': 'COMPLETED'},
                  ],
          },
          meta: {'page': 1, 'limit': 20, 'total': 1, 'totalPages': 1},
        );
      });

      await _show(tester, DriverTripHistoryScreen(repository: repository));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Kandy → Colombo'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Cancelled'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(asked, [null, 'CANCELLED']);
      expect(find.text('No cancelled trips.'), findsOneWidget);
    });
  });
}
