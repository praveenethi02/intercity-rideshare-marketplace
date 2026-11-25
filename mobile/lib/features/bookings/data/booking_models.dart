// A seat booking from the bookings API (SCRUM-78). See docs/api/changes/bookings.md.
// Money is LKR cents, the same as the trips feature.

import '../../trips/models/driver_vehicle.dart';

DateTime? _toLocalOrNull(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

/// The pickup or drop stop of a booking.
class BookingStop {
  final int order;
  final String name;
  final DateTime? plannedTime;

  const BookingStop({required this.order, required this.name, this.plannedTime});

  factory BookingStop.fromJson(Map<String, dynamic> j) => BookingStop(
        order: j['stopOrder'] as int,
        name: (j['name'] as String?) ?? 'Stop ${j['stopOrder']}',
        plannedTime: _toLocalOrNull(j['plannedAt']),
      );
}

/// One page of GET /bookings/mine.
class BookingPage {
  final List<Booking> items;
  final int page;
  final int totalPages;

  const BookingPage({required this.items, required this.page, required this.totalPages});

  bool get hasMore => page < totalPages;
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
  final String? driverId;

  // Journey details: only from GET /bookings/:id, and not from older servers.
  final TripVehicle? vehicle;

  /// From pickup to drop.
  final List<BookingStop> stops;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? tripCancelReason;

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
    this.driverId,
    this.vehicle,
    this.stops = const [],
    this.startedAt,
    this.completedAt,
    this.tripCancelReason,
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
      driverId: trip['driverId'] as String?,
      vehicle: trip['vehicle'] == null ? null : TripVehicle.fromJson(trip['vehicle'] as Map<String, dynamic>),
      stops: ((trip['stops'] as List<dynamic>?) ?? const [])
          .map((s) => BookingStop.fromJson(s as Map<String, dynamic>))
          .toList(),
      startedAt: _toLocalOrNull(trip['startedAt']),
      completedAt: _toLocalOrNull(trip['completedAt']),
      tripCancelReason: trip['cancelReason'] as String?,
    );
  }

  bool get isCancelled => status == 'CANCELLED';

  /// The same rule as the API: only a confirmed booking, and only before the trip starts.
  bool get canCancel => status == 'CONFIRMED' && tripStatus == 'SCHEDULED';
}
