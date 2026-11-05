// Trip data classes. They match docs/trips-api.md. Money is LKR cents.

double _toDouble(dynamic v) => (v as num).toDouble();
double? _toDoubleOrNull(dynamic v) => v == null ? null : (v as num).toDouble();
DateTime? _toLocalOrNull(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

class TripStatus {
  static const draft = 'DRAFT';
  static const scheduled = 'SCHEDULED';
  static const inProgress = 'IN_PROGRESS';
  static const completed = 'COMPLETED';
  static const cancelled = 'CANCELLED';

  static String label(String status) => switch (status) {
        draft => 'Draft',
        scheduled => 'Scheduled',
        inProgress => 'In progress',
        completed => 'Completed',
        cancelled => 'Cancelled',
        _ => status,
      };
}

class PricingMode {
  static const fixed = 'FIXED';
  static const auction = 'AUCTION';

  static String label(String mode) => mode == auction ? 'Seat auction' : 'Fixed price';
}

class TripStop {
  final int? order;
  final String name;
  final double lat;
  final double lng;
  final double? kmFromStart;
  final DateTime? plannedTime;

  const TripStop({
    this.order,
    required this.name,
    required this.lat,
    required this.lng,
    this.kmFromStart,
    this.plannedTime,
  });

  factory TripStop.fromJson(Map<String, dynamic> j) => TripStop(
        order: (j['order'] ?? j['stopOrder']) as int?,
        name: j['name'] as String,
        lat: _toDouble(j['lat']),
        lng: _toDouble(j['lng']),
        kmFromStart: _toDoubleOrNull(j['distanceFromStartKm']),
        plannedTime: _toLocalOrNull(j['plannedAt']),
      );

  /// Body format for POST /trips and /saved-routes
  Map<String, dynamic> toJson() => {
        'name': name,
        'lat': lat,
        'lng': lng,
        if (plannedTime != null) 'plannedAt': plannedTime!.toUtc().toIso8601String(),
      };

  /// Same place (used to stop duplicate consecutive stops)
  bool samePlaceAs(TripStop other) => name == other.name && lat == other.lat && lng == other.lng;
}

class TripLeg {
  final int legIndex;
  final int seatsReserved;
  final int seatsAvailable;

  const TripLeg({required this.legIndex, required this.seatsReserved, required this.seatsAvailable});

  factory TripLeg.fromJson(Map<String, dynamic> j) => TripLeg(
        legIndex: j['legIndex'] as int,
        seatsReserved: j['seatsReserved'] as int,
        seatsAvailable: j['seatsAvailable'] as int,
      );
}

/// What the driver may still change (mirrors editableFields() in the backend).
enum TripEditMode {
  /// DRAFT: everything
  full,

  /// SCHEDULED, no seats reserved: arrival, price, seats, notes
  limited,

  /// SCHEDULED with reserved seats: arrival and notes only
  notesOnly,

  /// IN_PROGRESS, COMPLETED, CANCELLED
  none,
}

class Trip {
  final String id;
  final String driverId;
  final String vehicleId;
  final String pricingMode;
  final String status;
  final DateTime departureTime;
  final DateTime? estArrivalTime;
  final int seatsOffered;
  final int basePriceCents;
  final double totalDistanceKm;
  final bool allowsCargo;
  final double? cargoCapacityKg;
  final String? notes;
  final String? cancelReason;
  final List<TripStop> stops;
  final List<TripLeg> legs;
  final int? seatsAvailableFullRoute;

  /// Start and end town names (always sent by the API)
  final String? originName;
  final String? destinationName;

  const Trip({
    required this.id,
    required this.driverId,
    required this.vehicleId,
    required this.pricingMode,
    required this.status,
    required this.departureTime,
    this.estArrivalTime,
    required this.seatsOffered,
    required this.basePriceCents,
    required this.totalDistanceKm,
    this.allowsCargo = false,
    this.cargoCapacityKg,
    this.notes,
    this.cancelReason,
    this.stops = const [],
    this.legs = const [],
    this.seatsAvailableFullRoute,
    this.originName,
    this.destinationName,
  });

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        driverId: j['driverId'] as String,
        vehicleId: j['vehicleId'] as String,
        pricingMode: j['pricingMode'] as String,
        status: j['status'] as String,
        departureTime: DateTime.parse(j['departureAt'] as String).toLocal(),
        estArrivalTime: _toLocalOrNull(j['estimatedArrivalAt']),
        seatsOffered: j['seatsOffered'] as int,
        basePriceCents: j['basePriceCents'] as int,
        totalDistanceKm: _toDouble(j['distanceKm']),
        allowsCargo: (j['allowsCargo'] as bool?) ?? false,
        cargoCapacityKg: _toDoubleOrNull(j['cargoCapacityKg']),
        notes: j['notes'] as String?,
        cancelReason: j['cancelReason'] as String?,
        stops: ((j['stops'] as List<dynamic>?) ?? const [])
            .map((s) => TripStop.fromJson(s as Map<String, dynamic>))
            .toList(),
        legs: ((j['legs'] as List<dynamic>?) ?? const [])
            .map((l) => TripLeg.fromJson(l as Map<String, dynamic>))
            .toList(),
        seatsAvailableFullRoute: j['seatsAvailable'] as int?,
        originName: j['originName'] as String?,
        destinationName: j['destinationName'] as String?,
      );

  String get origin => stops.isNotEmpty ? stops.first.name : (originName ?? '—');
  String get destination => stops.isNotEmpty ? stops.last.name : (destinationName ?? '—');
  String get routeLabel => '$origin → $destination';

  bool get hasReservations => legs.any((l) => l.seatsReserved > 0);
  bool get isUpcoming => status == TripStatus.draft || status == TripStatus.scheduled;
  bool get isActive => status == TripStatus.inProgress;
  bool get isPast => status == TripStatus.completed || status == TripStatus.cancelled;

  /// Driver may start up to 30 minutes before departure (backend rule).
  bool canStartAt(DateTime now) =>
      status == TripStatus.scheduled && !departureTime.subtract(const Duration(minutes: 30)).isAfter(now);

  TripEditMode get editMode {
    if (status == TripStatus.draft) return TripEditMode.full;
    if (status == TripStatus.scheduled) return hasReservations ? TripEditMode.notesOnly : TripEditMode.limited;
    return TripEditMode.none;
  }

  /// Name of the stop at each end of a leg, e.g. "Kadawatha → Kegalle"
  String legLabel(int legIndex) {
    if (legIndex + 1 >= stops.length) return 'Leg ${legIndex + 1}';
    return '${stops[legIndex].name} → ${stops[legIndex + 1].name}';
  }
}
