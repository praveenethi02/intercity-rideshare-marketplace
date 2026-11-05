import 'trip.dart';

/// A driver's reusable route template (GET /saved-routes)
class SavedRoute {
  final String id;
  final String name;
  final List<TripStop> stops;

  const SavedRoute({required this.id, required this.name, required this.stops});

  factory SavedRoute.fromJson(Map<String, dynamic> j) => SavedRoute(
        id: j['id'] as String,
        name: j['name'] as String,
        stops: (j['stops'] as List<dynamic>).map((s) => TripStop.fromJson(s as Map<String, dynamic>)).toList(),
      );

  String get summary => stops.map((s) => s.name).join(' → ');
}
