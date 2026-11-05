import '../../../core/api_client.dart';
import 'vehicle_models.dart';

/// Calls /api/v1/vehicles through the shared client, which adds the token and refreshes it.
class VehicleApi {
  VehicleApi(this._api);
  final ApiClient _api;

  static const _path = '/vehicles';

  List<Map<String, dynamic>> _list(ApiResponse res) => (res.data as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> _map(ApiResponse res) => res.data as Map<String, dynamic>;

  Future<List<VehicleTypeConfig>> getTypes() async =>
      _list(await _api.get('$_path/types')).map(VehicleTypeConfig.fromJson).toList();

  Future<List<Vehicle>> myVehicles() async => _list(await _api.get('$_path/mine')).map(Vehicle.fromJson).toList();

  Future<Vehicle> getVehicle(String id) async => Vehicle.fromJson(_map(await _api.get('$_path/$id')));

  Future<Vehicle> create(Map<String, dynamic> body) async => Vehicle.fromJson(_map(await _api.post(_path, body)));

  Future<Vehicle> update(String id, Map<String, dynamic> body) async =>
      Vehicle.fromJson(_map(await _api.patch('$_path/$id', body)));

  Future<Vehicle> setActive(String id, bool isActive) async =>
      Vehicle.fromJson(_map(await _api.patch('$_path/$id/active', {'isActive': isActive})));

  Future<List<VehicleDocument>> documents(String id) async =>
      _list(await _api.get('$_path/$id/documents')).map(VehicleDocument.fromJson).toList();

  Future<VehicleDocument> uploadDocument(String id, String docType, List<int> bytes, String fileName) async =>
      VehicleDocument.fromJson(_map(await _api.upload(
        '$_path/$id/documents',
        bytes: bytes,
        filename: fileName,
        fields: {'docType': docType},
      )));

  Future<VerificationInfo> verification(String id) async =>
      VerificationInfo.fromJson(_map(await _api.get('$_path/$id/verification')));

  Future<VerificationInfo> submit(String id) async =>
      VerificationInfo.fromJson(_map(await _api.post('$_path/$id/verification/submit')));
}
