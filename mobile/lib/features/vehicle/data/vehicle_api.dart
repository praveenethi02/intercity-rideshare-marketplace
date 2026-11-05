import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'vehicle_models.dart';

// M1's API client. It must give us a Dio with baseUrl (".../api/v1") and the
// Bearer token interceptor already set up.
// >>> If M1 named the provider differently, change ONLY the next two lines. <<<
import '../../../core/api_client.dart' as core;
final _dioProvider = core.dioProvider;

/// Path prefix relative to Dio's baseUrl. If M1's baseUrl does NOT end in /api/v1,
/// change this to '/api/v1/vehicles'.
const kVehiclesPath = '/vehicles';

class VehicleApi {
  VehicleApi(this._dio);
  final Dio _dio;

  // All responses use the envelope { success, message, data, meta }.
  dynamic _data(Response res) => (res.data as Map<String, dynamic>)['data'];

  List<Map<String, dynamic>> _list(Response res) => (_data(res) as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> _map(Response res) => _data(res) as Map<String, dynamic>;

  Future<List<VehicleTypeConfig>> getTypes() async =>
      _list(await _dio.get('$kVehiclesPath/types')).map(VehicleTypeConfig.fromJson).toList();

  Future<List<Vehicle>> myVehicles() async =>
      _list(await _dio.get('$kVehiclesPath/mine')).map(Vehicle.fromJson).toList();

  Future<Vehicle> getVehicle(String id) async => Vehicle.fromJson(_map(await _dio.get('$kVehiclesPath/$id')));

  Future<Vehicle> create(Map<String, dynamic> body) async =>
      Vehicle.fromJson(_map(await _dio.post(kVehiclesPath, data: body)));

  Future<Vehicle> update(String id, Map<String, dynamic> body) async =>
      Vehicle.fromJson(_map(await _dio.patch('$kVehiclesPath/$id', data: body)));

  Future<Vehicle> setActive(String id, bool isActive) async =>
      Vehicle.fromJson(_map(await _dio.patch('$kVehiclesPath/$id/active', data: {'isActive': isActive})));

  Future<List<VehicleDocument>> documents(String id) async =>
      _list(await _dio.get('$kVehiclesPath/$id/documents')).map(VehicleDocument.fromJson).toList();

  Future<VehicleDocument> uploadDocument(String id, String docType, String filePath, String fileName) async {
    final form = FormData.fromMap({
      'docType': docType,
      'file': await MultipartFile.fromFile(filePath, filename: fileName, contentType: _mediaType(fileName)),
    });
    return VehicleDocument.fromJson(_map(await _dio.post('$kVehiclesPath/$id/documents', data: form)));
  }

  Future<VerificationInfo> verification(String id) async =>
      VerificationInfo.fromJson(_map(await _dio.get('$kVehiclesPath/$id/verification')));

  Future<VerificationInfo> submit(String id) async =>
      VerificationInfo.fromJson(_map(await _dio.post('$kVehiclesPath/$id/verification/submit')));

  /// "/uploads/x.jpg" -> "http://host:port/uploads/x.jpg" for Image.network.
  String absoluteUrl(String fileUrl) {
    if (fileUrl.startsWith('http')) return fileUrl;
    return Uri.parse(_dio.options.baseUrl).origin + fileUrl;
  }

  // The backend only accepts jpg/png/pdf, so send the right content type.
  static DioMediaType _mediaType(String fileName) {
    final name = fileName.toLowerCase();
    if (name.endsWith('.pdf')) return DioMediaType('application', 'pdf');
    if (name.endsWith('.png')) return DioMediaType('image', 'png');
    return DioMediaType('image', 'jpeg');
  }
}

/// Turns a DioException into the API's "message" (+ first validation detail).
String apiErrorMessage(Object error) {
  if (error is DioException) {
    final body = error.response?.data;
    if (body is Map && body['message'] is String) {
      final details = (body['meta'] is Map) ? body['meta']['details'] : null;
      if (details is List && details.isNotEmpty && details.first is Map && details.first['message'] != null) {
        final first = details.first['message'].toString();
        return first == body['message'] ? first : '${body['message']}: $first';
      }
      return body['message'] as String;
    }
    if (error.type == DioExceptionType.connectionError || error.type == DioExceptionType.connectionTimeout) {
      return 'Cannot reach the server. Check your connection.';
    }
  }
  return 'Something went wrong. Please try again.';
}

final vehicleApiProvider = Provider<VehicleApi>((ref) => VehicleApi(ref.watch(_dioProvider)));

// ---------------- Riverpod providers used by the screens ----------------
final vehicleTypesProvider = FutureProvider<List<VehicleTypeConfig>>(
  (ref) => ref.watch(vehicleApiProvider).getTypes(),
);

final myVehiclesProvider = FutureProvider.autoDispose<List<Vehicle>>(
  (ref) => ref.watch(vehicleApiProvider).myVehicles(),
);

final vehicleProvider = FutureProvider.autoDispose.family<Vehicle, String>(
  (ref, id) => ref.watch(vehicleApiProvider).getVehicle(id),
);

final vehicleDocumentsProvider = FutureProvider.autoDispose.family<List<VehicleDocument>, String>(
  (ref, id) => ref.watch(vehicleApiProvider).documents(id),
);

final vehicleVerificationProvider = FutureProvider.autoDispose.family<VerificationInfo, String>(
  (ref, id) => ref.watch(vehicleApiProvider).verification(id),
);

/// Call after any change so every screen shows fresh data.
void refreshVehicle(WidgetRef ref, String id) {
  ref.invalidate(myVehiclesProvider);
  ref.invalidate(vehicleProvider(id));
  ref.invalidate(vehicleDocumentsProvider(id));
  ref.invalidate(vehicleVerificationProvider(id));
}
