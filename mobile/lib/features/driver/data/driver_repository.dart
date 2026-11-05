import '../../../core/api_client.dart';
import '../models/driver_models.dart';

/// Calls the driver API (see docs/api/changes/drivers.md).
class DriverRepository {
  DriverRepository(this.api);

  final ApiClient api;

  /// Signed links are built with the server's own address, which an emulator or phone may reach
  /// differently, so they are pointed at the address the app is already using.
  Map<String, dynamic> _withReachableUrl(Map<String, dynamic> document) {
    final link = Uri.parse(document['url'] as String);
    final base = Uri.parse(api.baseUrl);
    return {...document, 'url': link.replace(scheme: base.scheme, host: base.host, port: base.port).toString()};
  }

  DriverProfile _profile(ApiResponse r) {
    final json = (r.data as Map<String, dynamic>)['driver'] as Map<String, dynamic>;
    final documents = (json['documents'] as List).cast<Map<String, dynamic>>().map(_withReachableUrl).toList();
    return DriverProfile.fromJson({...json, 'documents': documents});
  }

  /// My profile, or null if this user has not registered as a driver yet.
  Future<DriverProfile?> myProfile() async {
    try {
      return _profile(await api.get('/drivers/me'));
    } on ApiException catch (e) {
      if (e.statusCode == 403 && e.code == 'FORBIDDEN') return null;
      rethrow;
    }
  }

  Future<DriverProfile> register({
    required String licenceNumber,
    required String licenceExpiry,
    required String nic,
    required String dateOfBirth,
    required String address,
    required String emergencyContactName,
    required String emergencyContactPhone,
  }) async =>
      _profile(await api.post('/drivers', {
        'licenceNumber': licenceNumber,
        'licenceExpiry': licenceExpiry,
        'nic': nic,
        'dateOfBirth': dateOfBirth,
        'address': address,
        'emergencyContactName': emergencyContactName,
        'emergencyContactPhone': emergencyContactPhone,
      }));

  Future<DriverProfile> update(Map<String, dynamic> changes) async => _profile(await api.patch('/drivers/me', changes));

  Future<DriverDocument> uploadDocument(String type, List<int> bytes, String filename) async {
    final r = await api.upload('/drivers/me/documents', bytes: bytes, filename: filename, fields: {'type': type});
    final json = (r.data as Map<String, dynamic>)['document'] as Map<String, dynamic>;
    return DriverDocument.fromJson(_withReachableUrl(json));
  }

  Future<DriverVerification> verification() async {
    final r = await api.get('/drivers/me/verification');
    return DriverVerification.fromJson((r.data as Map<String, dynamic>)['verification'] as Map<String, dynamic>);
  }

  Future<DriverEarnings> earnings({String? from, String? to}) async {
    final r = await api.get('/drivers/me/earnings', query: {
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
    return DriverEarnings.fromJson((r.data as Map<String, dynamic>)['earnings'] as Map<String, dynamic>);
  }

  Future<DriverTripPage> trips({String? status, int page = 1, int limit = 20}) async {
    final r = await api.get('/drivers/me/trips', query: {
      if (status != null) 'status': status,
      'page': '$page',
      'limit': '$limit',
    });
    final rows = ((r.data as Map<String, dynamic>)['trips'] as List).cast<Map<String, dynamic>>();
    return DriverTripPage(
      trips: rows.map(DriverTripSummary.fromJson).toList(),
      page: (r.meta['page'] as int?) ?? page,
      totalPages: (r.meta['totalPages'] as int?) ?? page,
    );
  }
}
