// The driver and vehicle a passenger sees (SCRUM-70).

/// A driver's public profile, from GET /drivers/:id.
class DriverPublicProfile {
  final String id;
  final String fullName; // short name, such as "Nimal S."
  final String? photoUrl;
  final double averageRating;
  final int ratingCount;
  final int completedTrips;
  final bool verified;

  const DriverPublicProfile({
    required this.id,
    required this.fullName,
    this.photoUrl,
    this.averageRating = 0,
    this.ratingCount = 0,
    this.completedTrips = 0,
    this.verified = false,
  });

  factory DriverPublicProfile.fromJson(Map<String, dynamic> j) => DriverPublicProfile(
        id: j['id'] as String,
        fullName: (j['fullName'] as String?) ?? 'Driver',
        photoUrl: j['photoUrl'] as String?,
        averageRating: ((j['averageRating'] as num?) ?? 0).toDouble(),
        ratingCount: (j['ratingCount'] as int?) ?? 0,
        completedTrips: (j['completedTrips'] as int?) ?? 0,
        verified: (j['verifiedDriver'] as bool?) ?? false,
      );

  /// "4.7 (12)" or "No ratings yet".
  String get ratingLabel => ratingCount == 0 ? 'No ratings yet' : '${averageRating.toStringAsFixed(1)} ($ratingCount)';
}

/// The vehicle of a trip. The plate number comes only with a booking, and only while it is needed.
class TripVehicle {
  final String type; // CAR, THREE_WHEELER, ...
  final String make;
  final String model;
  final int year;
  final String color;
  final String? plateNumber;

  const TripVehicle({
    required this.type,
    required this.make,
    required this.model,
    required this.year,
    required this.color,
    this.plateNumber,
  });

  factory TripVehicle.fromJson(Map<String, dynamic> j) => TripVehicle(
        type: j['type'] as String,
        make: j['make'] as String,
        model: j['model'] as String,
        year: j['year'] as int,
        color: j['color'] as String,
        plateNumber: j['plateNumber'] as String?,
      );

  /// The same labels as the vehicle types in the API (vehicleTypes.js).
  String get typeLabel => switch (type) {
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
        _ => type.isEmpty ? 'Vehicle' : '${type[0]}${type.substring(1).toLowerCase().replaceAll('_', ' ')}',
      };
}
