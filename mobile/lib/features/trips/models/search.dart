import '../../../core/formatters.dart';
import 'trip.dart';

double? _toDoubleOrNull(dynamic v) => v == null ? null : (v as num).toDouble();
DateTime? _toLocalOrNull(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

/// Result order for GET /trips/search (`sort`). The server sorts every page.
class SearchSort {
  static const earliest = 'earliest';
  static const cheapest = 'cheapest';
  static const closest = 'closest';
  static const values = [earliest, cheapest, closest];

  static String label(String sort) => switch (sort) {
        cheapest => 'Cheapest',
        closest => 'Closest pickup',
        _ => 'Earliest',
      };
}

/// "HH:mm" for the departAfter / departBefore filters (Sri Lankan clock time).
String clockTime(int hour, int minute) => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// "06:30" -> "6:30 AM"
String formatClockTime(String hhmm) {
  final parts = hhmm.split(':');
  return formatTime(DateTime(2000, 1, 1, int.parse(parts[0]), int.parse(parts[1])));
}

/// Optional search filters (SCRUM-69). All of them are applied by the server, so they cover every page.
class SearchFilters {
  /// Highest seat price for the passenger's part of the route, in LKR cents.
  final int? maxPriceCents;

  /// Pickup time range, "HH:mm", both ends included.
  final String? departAfter;
  final String? departBefore;

  /// Only trips that take parcels.
  final bool allowsCargo;

  /// Only trips that take at least this much cargo.
  final double? minCargoKg;

  const SearchFilters({
    this.maxPriceCents,
    this.departAfter,
    this.departBefore,
    this.allowsCargo = false,
    this.minCargoKg,
  });

  static const none = SearchFilters();

  /// How many filters are on (the departure range counts once).
  int get activeCount =>
      (maxPriceCents != null ? 1 : 0) +
      (departAfter != null || departBefore != null ? 1 : 0) +
      (allowsCargo ? 1 : 0) +
      (minCargoKg != null ? 1 : 0);

  bool get isEmpty => activeCount == 0;

  Map<String, String> toQuery() => {
        if (maxPriceCents != null) 'maxPriceCents': '$maxPriceCents',
        if (departAfter != null) 'departAfter': departAfter!,
        if (departBefore != null) 'departBefore': departBefore!,
        if (allowsCargo) 'allowsCargo': 'true',
        if (minCargoKg != null) 'minCargoKg': _number(minCargoKg!),
      };

  /// 50.0 -> "50", 12.5 -> "12.5"
  static String _number(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      other.maxPriceCents == maxPriceCents &&
      other.departAfter == departAfter &&
      other.departBefore == departBefore &&
      other.allowsCargo == allowsCargo &&
      other.minCargoKg == minCargoKg;

  @override
  int get hashCode => Object.hash(maxPriceCents, departAfter, departBefore, allowsCargo, minCargoKg);
}

/// Same town, or a custom place with the same coordinates (about 1 m apart or less).
bool isSamePlace(TripStop a, TripStop b) =>
    a.name.trim().toLowerCase() == b.name.trim().toLowerCase() ||
    ((a.lat - b.lat).abs() < 0.00001 && (a.lng - b.lng).abs() < 0.00001);

/// Passenger search input for GET /trips/search
class SearchQuery {
  final TripStop from;
  final TripStop to;
  final DateTime date;
  final int seats;
  final String? pricingMode; // null = any
  final double? radiusKm;
  final SearchFilters filters;
  final String sort;

  const SearchQuery({
    required this.from,
    required this.to,
    required this.date,
    this.seats = 1,
    this.pricingMode,
    this.radiusKm,
    this.filters = SearchFilters.none,
    this.sort = SearchSort.earliest,
  });

  static const pageSize = 20;

  SearchQuery copyWith({SearchFilters? filters, String? sort}) => SearchQuery(
        from: from,
        to: to,
        date: date,
        seats: seats,
        pricingMode: pricingMode,
        radiusKm: radiusKm,
        filters: filters ?? this.filters,
        sort: sort ?? this.sort,
      );

  /// Same route, day, seats and price type (used to keep recent searches unique).
  bool sameSearchAs(SearchQuery other) =>
      isSamePlace(from, other.from) &&
      isSamePlace(to, other.to) &&
      isoDate(date) == isoDate(other.date) &&
      seats == other.seats &&
      pricingMode == other.pricingMode;

  Map<String, String> toQuery({int page = 1, int limit = pageSize}) => {
        'fromLat': '${from.lat}',
        'fromLng': '${from.lng}',
        'toLat': '${to.lat}',
        'toLng': '${to.lng}',
        'date': isoDate(date),
        'seats': '$seats',
        if (pricingMode != null) 'pricingMode': pricingMode!,
        if (radiusKm != null) 'radiusKm': '$radiusKm',
        ...filters.toQuery(),
        'sort': sort,
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

  /// Seats the driver offers (null from older servers).
  final int? seatsOffered;

  /// When the whole trip is expected to end (null if the driver did not set it).
  final DateTime? estimatedArrivalTime;

  /// Cargo the trip can take, in kg (null when it takes no cargo).
  final double? cargoCapacityKg;

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
    this.seatsOffered,
    this.estimatedArrivalTime,
    this.cargoCapacityKg,
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
      seatsOffered: j['seatsOffered'] as int?,
      estimatedArrivalTime: _toLocalOrNull(j['estimatedArrivalAt']),
      cargoCapacityKg: _toDoubleOrNull(j['cargoCapacityKg']),
    );
  }

  /// Pickup time: the stop's planned time, else departure time.
  DateTime get pickupTime => pickup.plannedTime ?? departureTime;
  double get walkingKm => pickupDistanceKm + dropDistanceKm;
}

/// One page of search results. [total] counts every match on the server, after the filters.
class SearchPage {
  final List<TripSearchResult> items;
  final int total;
  final double radiusKm;
  final int page;
  const SearchPage({required this.items, required this.total, required this.radiusKm, this.page = 1});
}

/// One leg of the passenger's part of the route, from GET /trips/:id/availability.
class SegmentLeg {
  final int legIndex;
  final String fromName;
  final String toName;
  final int seatsAvailable;

  const SegmentLeg(
      {required this.legIndex, required this.fromName, required this.toName, required this.seatsAvailable});

  factory SegmentLeg.fromJson(Map<String, dynamic> j) => SegmentLeg(
        legIndex: j['legIndex'] as int,
        fromName: j['fromName'] as String,
        toName: j['toName'] as String,
        seatsAvailable: j['seatsAvailable'] as int,
      );
}

/// GET /trips/:id/availability
class SegmentAvailability {
  final String tripId;
  final int fromStop;
  final int toStop;
  final int seatsAvailable;
  final int segmentPriceCents;

  /// Null from older servers; the detail screen then uses the trip's values.
  final int? seatsOffered;
  final bool? allowsCargo;
  final double? cargoCapacityKg;
  final List<SegmentLeg> legs;

  const SegmentAvailability({
    required this.tripId,
    required this.fromStop,
    required this.toStop,
    required this.seatsAvailable,
    required this.segmentPriceCents,
    this.seatsOffered,
    this.allowsCargo,
    this.cargoCapacityKg,
    this.legs = const [],
  });

  factory SegmentAvailability.fromJson(Map<String, dynamic> j) => SegmentAvailability(
        tripId: j['tripId'] as String,
        fromStop: j['fromStop'] as int,
        toStop: j['toStop'] as int,
        seatsAvailable: j['seatsAvailable'] as int,
        segmentPriceCents: j['segmentPriceCents'] as int,
        seatsOffered: j['seatsOffered'] as int?,
        allowsCargo: j['allowsCargo'] as bool?,
        cargoCapacityKg: _toDoubleOrNull(j['cargoCapacityKg']),
        legs: ((j['legs'] as List<dynamic>?) ?? const [])
            .map((l) => SegmentLeg.fromJson(l as Map<String, dynamic>))
            .toList(),
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

/// The last five searches of this app session, newest first. Kept in memory only.
class RecentSearches {
  RecentSearches();

  /// The app-wide history. Screens use this unless a test passes its own.
  static final instance = RecentSearches();

  static const max = 5;
  final List<SearchQuery> _items = [];

  List<SearchQuery> get items => List.unmodifiable(_items);

  /// Moves [query] to the front. A search for the same route, day and seats replaces the older one.
  void add(SearchQuery query) {
    _items
      ..removeWhere((q) => q.sameSearchAs(query))
      ..insert(0, query.copyWith(filters: SearchFilters.none, sort: SearchSort.earliest));
    if (_items.length > max) _items.removeRange(max, _items.length);
  }

  void clear() => _items.clear();
}
