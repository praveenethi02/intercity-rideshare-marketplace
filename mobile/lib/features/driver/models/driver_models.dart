/// The documents a driver uploads, in the order they are shown. All five are needed for review.
const driverDocumentTypes = ['LICENCE_FRONT', 'LICENCE_BACK', 'NIC_FRONT', 'NIC_BACK', 'PROFILE_PHOTO'];

String driverDocumentLabel(String type) => switch (type) {
      'LICENCE_FRONT' => 'Driving licence (front)',
      'LICENCE_BACK' => 'Driving licence (back)',
      'NIC_FRONT' => 'NIC (front)',
      'NIC_BACK' => 'NIC (back)',
      'PROFILE_PHOTO' => 'Profile photo',
      _ => type,
    };

DateTime? _time(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

class DriverDocument {
  final String id;
  final String type;

  /// Short-lived signed link, already pointed at the API address the app is using.
  final String url;
  final DateTime? uploadedAt;

  const DriverDocument({required this.id, required this.type, required this.url, this.uploadedAt});

  factory DriverDocument.fromJson(Map<String, dynamic> j) => DriverDocument(
        id: j['id'] as String,
        type: j['type'] as String,
        url: j['url'] as String,
        uploadedAt: _time(j['uploadedAt']),
      );

  bool get isPdf => Uri.parse(url).path.toLowerCase().endsWith('.pdf');
}

class DriverProfile {
  final String id;
  final String licenceNumber;
  final String licenceExpiry;
  final String? dateOfBirth;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String verification; // PENDING | APPROVED | REJECTED
  final String? rejectionReason;
  final DateTime? verifiedAt;
  final String accountStatus; // ACTIVE | SUSPENDED | DEACTIVATED
  final double averageRating;
  final int ratingCount;
  final int completedTrips;
  final List<DriverDocument> documents;

  const DriverProfile({
    required this.id,
    required this.licenceNumber,
    required this.licenceExpiry,
    this.dateOfBirth,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    required this.verification,
    this.rejectionReason,
    this.verifiedAt,
    required this.accountStatus,
    required this.averageRating,
    required this.ratingCount,
    required this.completedTrips,
    required this.documents,
  });

  factory DriverProfile.fromJson(Map<String, dynamic> j) => DriverProfile(
        id: j['id'] as String,
        licenceNumber: j['licenceNumber'] as String,
        licenceExpiry: j['licenceExpiry'] as String,
        dateOfBirth: j['dateOfBirth'] as String?,
        address: j['address'] as String?,
        emergencyContactName: j['emergencyContactName'] as String?,
        emergencyContactPhone: j['emergencyContactPhone'] as String?,
        verification: j['verification'] as String,
        rejectionReason: j['rejectionReason'] as String?,
        verifiedAt: _time(j['verifiedAt']),
        accountStatus: j['accountStatus'] as String,
        averageRating: (j['averageRating'] as num).toDouble(),
        ratingCount: j['ratingCount'] as int,
        completedTrips: j['completedTrips'] as int,
        documents: (j['documents'] as List)
            .cast<Map<String, dynamic>>()
            .map(DriverDocument.fromJson)
            .toList(),
      );

  bool get isApproved => verification == 'APPROVED';

  /// The same rule the backend applies before a driver can publish trips.
  bool get canOfferTrips => isApproved && accountStatus == 'ACTIVE';
}

class DriverVerification {
  final String status;
  final String? reason;
  final List<String> missingDocuments;
  final DateTime? submittedAt;
  final DateTime? decidedAt;

  const DriverVerification({
    required this.status,
    this.reason,
    required this.missingDocuments,
    this.submittedAt,
    this.decidedAt,
  });

  factory DriverVerification.fromJson(Map<String, dynamic> j) => DriverVerification(
        status: j['status'] as String,
        reason: j['reason'] as String?,
        missingDocuments: (j['missingDocuments'] as List).cast<String>(),
        submittedAt: _time(j['submittedAt']),
        decidedAt: _time(j['decidedAt']),
      );
}

class DriverEarnings {
  final String currency;
  final int seatEarnings;
  final int cargoEarnings;
  final int platformFees;
  final int paidOut;
  final int pendingPayout;
  final int completedTrips;

  const DriverEarnings({
    required this.currency,
    required this.seatEarnings,
    required this.cargoEarnings,
    required this.platformFees,
    required this.paidOut,
    required this.pendingPayout,
    required this.completedTrips,
  });

  factory DriverEarnings.fromJson(Map<String, dynamic> j) => DriverEarnings(
        currency: j['currency'] as String,
        seatEarnings: j['seatEarnings'] as int,
        cargoEarnings: j['cargoEarnings'] as int,
        platformFees: j['platformFees'] as int,
        paidOut: j['paidOut'] as int,
        pendingPayout: j['pendingPayout'] as int,
        completedTrips: j['completedTrips'] as int,
      );
}

class DriverTripSummary {
  final String id;
  final String originName;
  final String destinationName;
  final DateTime? departureAt;
  final String status;
  final int? seatsOffered;
  final int? basePriceCents;
  final String? cancelReason;

  const DriverTripSummary({
    required this.id,
    required this.originName,
    required this.destinationName,
    this.departureAt,
    required this.status,
    this.seatsOffered,
    this.basePriceCents,
    this.cancelReason,
  });

  factory DriverTripSummary.fromJson(Map<String, dynamic> j) => DriverTripSummary(
        id: j['id'] as String,
        originName: (j['originName'] as String?) ?? '',
        destinationName: (j['destinationName'] as String?) ?? '',
        departureAt: _time(j['departureAt']),
        status: j['status'] as String,
        seatsOffered: j['seatsOffered'] as int?,
        basePriceCents: j['basePriceCents'] as int?,
        cancelReason: j['cancelReason'] as String?,
      );
}

class DriverTripPage {
  final List<DriverTripSummary> trips;
  final int page;
  final int totalPages;

  const DriverTripPage({required this.trips, required this.page, required this.totalPages});

  bool get hasMore => page < totalPages;
}
