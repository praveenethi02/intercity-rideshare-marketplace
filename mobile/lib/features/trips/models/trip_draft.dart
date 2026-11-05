import 'trip.dart';

/// Rules copied from the backend so the app can warn before sending.
/// Keep these in sync with backend/src/modules/trips/trip.constants.js.
class TripRules {
  static const minLeadTime = Duration(minutes: 30);
  static const maxDaysAhead = 60;
  static const minStops = 2;
  static const maxStops = 15;
  static const maxSeats = 14;
  static const maxNotes = 500;
  static const maxCargoKg = 2000.0;

  /// Returns an error message, or null if OK.
  static String? checkDeparture(DateTime departure, DateTime now) {
    if (departure.isBefore(now.add(minLeadTime))) return 'Departure must be at least 30 minutes from now';
    if (departure.isAfter(now.add(const Duration(days: maxDaysAhead)))) {
      return 'Departure cannot be more than $maxDaysAhead days ahead';
    }
    return null;
  }

  static String? checkArrival(DateTime? arrival, DateTime departure) {
    if (arrival == null) return null;
    if (!arrival.isAfter(departure)) return 'Arrival must be after departure';
    return null;
  }

  static String? checkStops(List<TripStop> stops) {
    if (stops.length < minStops) return 'Add at least a start and an end point';
    if (stops.length > maxStops) return 'A trip can have at most $maxStops stops';
    for (var i = 1; i < stops.length; i++) {
      if (stops[i].samePlaceAs(stops[i - 1])) return '"${stops[i].name}" is repeated next to itself';
    }
    return null;
  }
}

/// Body for POST /trips
class TripDraft {
  final String vehicleId;
  final String pricingMode;
  final DateTime departureTime;
  final DateTime? estArrivalTime;
  final int seatsOffered;
  final int basePriceCents;
  final bool allowsCargo;
  final double? cargoCapacityKg;
  final String? notes;
  final List<TripStop> stops;

  const TripDraft({
    required this.vehicleId,
    required this.pricingMode,
    required this.departureTime,
    this.estArrivalTime,
    required this.seatsOffered,
    required this.basePriceCents,
    this.allowsCargo = false,
    this.cargoCapacityKg,
    this.notes,
    required this.stops,
  });

  Map<String, dynamic> toJson() => {
        'vehicleId': vehicleId,
        'pricingMode': pricingMode,
        'departureAt': departureTime.toUtc().toIso8601String(),
        if (estArrivalTime != null) 'estimatedArrivalAt': estArrivalTime!.toUtc().toIso8601String(),
        'seatsOffered': seatsOffered,
        'basePriceCents': basePriceCents,
        'allowsCargo': allowsCargo,
        if (allowsCargo && cargoCapacityKg != null) 'cargoCapacityKg': cargoCapacityKg,
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
        'stops': stops.map((s) => s.toJson()).toList(),
      };
}
