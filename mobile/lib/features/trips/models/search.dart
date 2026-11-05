import '../../../core/formatters.dart';
import 'trip.dart';

/// Passenger search input for GET /trips/search
class SearchQuery {
  final TripStop from;
  final TripStop to;
  final DateTime date;
  final int seats;
  final String? pricingMode; // null = any
  final double? radiusKm;

  const SearchQuery({
    required this.from,
    required this.to,
    required this.date,
    this.seats = 1,
    this.pricingMode,
    this.radiusKm,
  });

  Map<String, String> toQuery({int page = 1, int limit = 50}) => {
        'fromLat': '${from.lat}',
        'fromLng': '${from.lng}',
        'toLat': '${to.lat}',
        'toLng': '${to.lng}',
        'date': isoDate(date),
        'seats': '$seats',
        if (pricingMode != null) 'pricingMode': pricingMode!,
        if (radiusKm != null) 'radiusKm': '$radiusKm',
        'page': '$page',
        'limit': '$limit',
      };
}

class TripSearchResult {
  final String tripId;
  final String driverId;
  final String pricingMode;
  final DateTime departureTime;
  final bool allowsCargo;
  final TripStop pickup;
  final TripStop drop;
  final double pickupDistanceKm;
  final double dropDistanceKm;
  final double segmentDistanceKm;
  final int seatsAvailable;
  final int segmentPriceCents;

  const TripSearchResult({
    required this.tripId,
    required this.driverId,
    required this.pricingMode,
    required this.departureTime,
    required this.allowsCargo,
    required this.pickup,
    required this.drop,
    required this.pickupDistanceKm,
    required this.dropDistanceKm,
    required this.segmentDistanceKm,
    required this.seatsAvailable,
    required this.segmentPriceCents,
  });

  factory TripSearchResult.fromJson(Map<String, dynamic> j) {
    final pickup = j['pickup'] as Map<String, dynamic>;
    final drop = j['drop'] as Map<String, dynamic>;
    return TripSearchResult(
      tripId: j['tripId'] as String,
      driverId: j['driverId'] as String,
      pricingMode: j['pricingMode'] as String,
      departureTime: DateTime.parse(j['departureAt'] as String).toLocal(),
      allowsCargo: (j['allowsCargo'] as bool?) ?? false,
      pickup: TripStop.fromJson(pickup),
      drop: TripStop.fromJson(drop),
      pickupDistanceKm: (pickup['distanceFromYouKm'] as num).toDouble(),
      dropDistanceKm: (drop['distanceFromYourDestinationKm'] as num).toDouble(),
      segmentDistanceKm: (j['segmentDistanceKm'] as num).toDouble(),
      seatsAvailable: j['seatsAvailable'] as int,
      segmentPriceCents: j['segmentPriceCents'] as int,
    );
  }

  /// Pickup time: the stop's planned time, else departure time.
  DateTime get pickupTime => pickup.plannedTime ?? departureTime;
  double get walkingKm => pickupDistanceKm + dropDistanceKm;
}

class SearchPage {
  final List<TripSearchResult> items;
  final int total;
  final double radiusKm;
  const SearchPage({required this.items, required this.total, required this.radiusKm});
}

/// GET /trips/:id/availability
class SegmentAvailability {
  final String tripId;
  final int fromStop;
  final int toStop;
  final int seatsAvailable;
  final int segmentPriceCents;

  const SegmentAvailability({
    required this.tripId,
    required this.fromStop,
    required this.toStop,
    required this.seatsAvailable,
    required this.segmentPriceCents,
  });

  factory SegmentAvailability.fromJson(Map<String, dynamic> j) => SegmentAvailability(
        tripId: j['tripId'] as String,
        fromStop: j['fromStop'] as int,
        toStop: j['toStop'] as int,
        seatsAvailable: j['seatsAvailable'] as int,
        segmentPriceCents: j['segmentPriceCents'] as int,
      );
}

/// Handed to the Booking / Auction module when the passenger taps Book or Bid.
class SegmentSelection {
  final String tripId;
  final int fromStop;
  final int toStop;
  final int seats;
  final String pricingMode;

  /// FIXED: price per seat. AUCTION: suggested starting bid per seat.
  final int pricePerSeatCents;

  const SegmentSelection({
    required this.tripId,
    required this.fromStop,
    required this.toStop,
    required this.seats,
    required this.pricingMode,
    required this.pricePerSeatCents,
  });
}
