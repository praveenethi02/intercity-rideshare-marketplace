// Plain data classes for the vehicle feature (JSON is camelCase, same as the API).

class VehicleTypeConfig {
  final String type;
  final String label;
  final int minSeats;
  final int maxSeats;
  final int maxCargoKg;
  final int maxCargoVolumeL;
  final bool allowsCargo;

  const VehicleTypeConfig({
    required this.type,
    required this.label,
    required this.minSeats,
    required this.maxSeats,
    required this.maxCargoKg,
    required this.maxCargoVolumeL,
    required this.allowsCargo,
  });

  factory VehicleTypeConfig.fromJson(Map<String, dynamic> j) => VehicleTypeConfig(
        type: j['type'] as String,
        label: (j['label'] ?? j['type']) as String,
        minSeats: j['minSeats'] as int,
        maxSeats: j['maxSeats'] as int,
        maxCargoKg: (j['maxCargoKg'] ?? 0) as int,
        maxCargoVolumeL: (j['maxCargoVolumeL'] ?? 0) as int,
        allowsCargo: (j['allowsCargo'] ?? false) as bool,
      );
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
  bool get canSubmit => verificationStatus == 'NOT_SUBMITTED' || verificationStatus == 'REJECTED';

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
