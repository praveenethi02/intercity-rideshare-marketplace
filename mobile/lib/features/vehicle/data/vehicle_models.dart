// Plain data classes for the vehicle feature (JSON is camelCase, same as the API).

/// A make and its common models, for the add-vehicle dropdowns.
class VehicleBrand {
  final String name;
  final List<String> models;

  const VehicleBrand({required this.name, required this.models});

  factory VehicleBrand.fromJson(Map<String, dynamic> j) => VehicleBrand(
        name: j['name'] as String,
        models: (j['models'] as List? ?? const []).cast<String>(),
      );
}

class VehicleTypeConfig {
  final String type;
  final String label;
  final int minSeats;
  final int maxSeats;
  final int maxCargoKg;
  final int maxCargoVolumeL;
  final bool allowsCargo;

  /// Suggestions only. The driver can pick "Other" and type any make or model.
  final List<VehicleBrand> brands;

  const VehicleTypeConfig({
    required this.type,
    required this.label,
    required this.minSeats,
    required this.maxSeats,
    required this.maxCargoKg,
    required this.maxCargoVolumeL,
    required this.allowsCargo,
    this.brands = const [],
  });

  factory VehicleTypeConfig.fromJson(Map<String, dynamic> j) => VehicleTypeConfig(
        type: j['type'] as String,
        label: (j['label'] ?? j['type']) as String,
        minSeats: j['minSeats'] as int,
        maxSeats: j['maxSeats'] as int,
        maxCargoKg: (j['maxCargoKg'] ?? 0) as int,
        maxCargoVolumeL: (j['maxCargoVolumeL'] ?? 0) as int,
        allowsCargo: (j['allowsCargo'] ?? false) as bool,
        brands: [
          for (final b in (j['brands'] as List? ?? const [])) VehicleBrand.fromJson(b as Map<String, dynamic>),
        ],
      );

  VehicleBrand? brandNamed(String name) {
    for (final brand in brands) {
      if (brand.name == name) return brand;
    }
    return null;
  }
}

class Vehicle {
  final String id;
  final String vehicleType;
  final String make;
  final String model;
  final int year;
  final String color;
  final String plateNumber;
  final int totalSeats;
  final int passengerSeats;
  final int cargoCapacityKg;
  final int cargoVolumeL;
  final String verificationStatus; // NOT_SUBMITTED | PENDING | APPROVED | REJECTED
  final String? rejectionReason;
  final bool isActive;

  const Vehicle({
    required this.id,
    required this.vehicleType,
    required this.make,
    required this.model,
    required this.year,
    required this.color,
    required this.plateNumber,
    required this.totalSeats,
    required this.passengerSeats,
    required this.cargoCapacityKg,
    required this.cargoVolumeL,
    required this.verificationStatus,
    required this.rejectionReason,
    required this.isActive,
  });

  String get title => '$make $model ($year)';

  /// "THREE_WHEELER" -> "Three-wheeler". The same labels as the API (vehicleTypes.js).
  String get typeLabel => switch (vehicleType) {
        'CAR' => 'Car',
        'THREE_WHEELER' => 'Three-wheeler',
        'MOTORBIKE' => 'Motorbike',
        'SUV' => 'SUV',
        'VAN' => 'Van',
        'MINIBUS' => 'Mini bus',
        'BUS' => 'Bus',
        'PICKUP' => 'Pickup / Cab',
        'LORRY' => 'Lorry',
        // A type added to the API later: "NEW_TYPE" -> "New type".
        _ => vehicleType.isEmpty
            ? 'Vehicle'
            : '${vehicleType[0]}${vehicleType.substring(1).toLowerCase().replaceAll('_', ' ')}',
      };
  bool get canSubmit => verificationStatus == 'NOT_SUBMITTED' || verificationStatus == 'REJECTED';

  /// Same rule as the API: only an APPROVED, active vehicle can be used for trips.
  bool get isUsableForTrips => verificationStatus == 'APPROVED' && isActive;

  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
        id: j['id'] as String,
        vehicleType: j['vehicleType'] as String,
        make: j['make'] as String,
        model: j['model'] as String,
        year: j['year'] as int,
        color: j['color'] as String,
        plateNumber: j['plateNumber'] as String,
        totalSeats: j['totalSeats'] as int,
        passengerSeats: j['passengerSeats'] as int,
        cargoCapacityKg: (j['cargoCapacityKg'] ?? 0) as int,
        cargoVolumeL: (j['cargoVolumeL'] ?? 0) as int,
        verificationStatus: j['verificationStatus'] as String,
        rejectionReason: j['rejectionReason'] as String?,
        isActive: (j['isActive'] ?? true) as bool,
      );
}

class VehicleDocument {
  final String id;
  final String docType;
  final String fileUrl;
  final String status; // UPLOADED | ACCEPTED | REJECTED
  final DateTime? uploadedAt;

  const VehicleDocument({
    required this.id,
    required this.docType,
    required this.fileUrl,
    required this.status,
    this.uploadedAt,
  });

  // fileUrl is a signed link, so the extension comes before the query string.
  bool get isPdf => fileUrl.split('?').first.toLowerCase().endsWith('.pdf');

  factory VehicleDocument.fromJson(Map<String, dynamic> j) => VehicleDocument(
        id: j['id'] as String,
        docType: j['docType'] as String,
        fileUrl: j['fileUrl'] as String,
        status: j['status'] as String,
        uploadedAt: j['uploadedAt'] == null ? null : DateTime.tryParse(j['uploadedAt'] as String),
      );
}

class VerificationInfo {
  final String status;
  final List<String> missingDocuments;
  final String? rejectionReason;

  const VerificationInfo({required this.status, required this.missingDocuments, this.rejectionReason});

  bool get canSubmit => (status == 'NOT_SUBMITTED' || status == 'REJECTED') && missingDocuments.isEmpty;

  factory VerificationInfo.fromJson(Map<String, dynamic> j) => VerificationInfo(
        status: j['status'] as String,
        missingDocuments: (j['missingDocuments'] as List? ?? const []).cast<String>(),
        rejectionReason: j['rejectionReason'] as String?,
      );
}

/// The vehicle a driver's new trips use: their oldest approved, active vehicle.
Vehicle? usableVehicle(List<Vehicle> vehicles) {
  for (final vehicle in vehicles) {
    if (vehicle.isUsableForTrips) return vehicle;
  }
  return null;
}

/// Explains why a driver with these vehicles cannot create a trip yet.
String noUsableVehicleMessage(List<Vehicle> vehicles) {
  if (vehicles.isEmpty) {
    return 'You have no vehicles yet. Add a vehicle and get it approved before creating a trip.';
  }
  if (vehicles.any((v) => v.verificationStatus == 'APPROVED')) {
    return 'Your approved vehicle is not active. Activate it before creating a trip.';
  }
  if (vehicles.any((v) => v.verificationStatus == 'PENDING')) {
    return 'Your vehicle is waiting for admin approval. You can create a trip once it is approved.';
  }
  return 'You have no approved vehicle. Submit a vehicle for approval before creating a trip.';
}

/// All document types, in the order the documents screen shows them.
const vehicleDocTypes = <String, String>{
  'REGISTRATION_CERT': 'Registration certificate (CR)',
  'REVENUE_LICENSE': 'Revenue licence',
  'INSURANCE': 'Insurance certificate',
  'PHOTO_FRONT': 'Photo – front (plate visible)',
  'PHOTO_BACK': 'Photo – back',
  'PHOTO_INTERIOR': 'Photo – interior / seats',
};

const requiredVehicleDocTypes = {'REGISTRATION_CERT', 'REVENUE_LICENSE', 'INSURANCE', 'PHOTO_FRONT'};

/// Fields that send an APPROVED vehicle back to PENDING when edited (same rule as the API).
const reverifyFields = {'plateNumber', 'vehicleType', 'totalSeats', 'passengerSeats', 'cargoCapacityKg', 'cargoVolumeL'};
