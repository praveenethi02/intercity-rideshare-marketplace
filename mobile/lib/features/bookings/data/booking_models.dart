// A seat booking from the bookings API (SCRUM-78). See docs/api/changes/bookings.md.
// Money is LKR cents, the same as the trips feature.

/// The pickup or drop stop of a booking.
class BookingStop {
  final int order;
  final String name;
  final DateTime? plannedTime;

  const BookingStop({required this.order, required this.name, this.plannedTime});

  factory BookingStop.fromJson(Map<String, dynamic> j) => BookingStop(
        order: j['stopOrder'] as int,
        name: (j['name'] as String?) ?? 'Stop ${j['stopOrder']}',
        plannedTime: j['plannedAt'] == null ? null : DateTime.parse(j['plannedAt'] as String).toLocal(),
      );
}

class Booking {
  final String id;
  final String reference;
  final String status; // CONFIRMED | CANCELLED
  final String tripId;
  final String tripStatus; // SCHEDULED | IN_PROGRESS | COMPLETED | CANCELLED
  final String originName;
  final String destinationName;
  final DateTime departureTime;
  final BookingStop pickup;
  final BookingStop drop;
  final int seats;
  final int pricePerSeatCents;
  final int totalCents;
  final String? cancelReason;

  const Booking({
    required this.id,
    required this.reference,
    required this.status,
    required this.tripId,
    required this.tripStatus,
    required this.originName,
    required this.destinationName,
    required this.departureTime,
    required this.pickup,
    required this.drop,
    required this.seats,
    required this.pricePerSeatCents,
    required this.totalCents,
    this.cancelReason,
  });

  factory Booking.fromJson(Map<String, dynamic> j) {
    final trip = j['trip'] as Map<String, dynamic>;
    return Booking(
      id: j['id'] as String,
      reference: j['reference'] as String,
      status: j['status'] as String,
      tripId: j['tripId'] as String,
      tripStatus: trip['status'] as String,
      originName: trip['originName'] as String,
      destinationName: trip['destinationName'] as String,
      departureTime: DateTime.parse(trip['departureAt'] as String).toLocal(),
      pickup: BookingStop.fromJson(j['pickup'] as Map<String, dynamic>),
      drop: BookingStop.fromJson(j['drop'] as Map<String, dynamic>),
      seats: j['seats'] as int,
      pricePerSeatCents: j['pricePerSeatCents'] as int,
      totalCents: j['totalCents'] as int,
      cancelReason: j['cancelReason'] as String?,
    );
  }

  bool get isCancelled => status == 'CANCELLED';

  /// The same rule as the API: only a confirmed booking, and only before the trip starts.
  bool get canCancel => status == 'CONFIRMED' && tripStatus == 'SCHEDULED';
}