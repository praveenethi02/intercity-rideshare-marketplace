import '../../../core/api_client.dart';
import '../models/saved_route.dart';
import '../models/search.dart';
import '../models/trip.dart';
import '../models/trip_draft.dart';

/// Every call the trips feature makes to the backend.
class TripRepository {
  final ApiClient api;
  const TripRepository(this.api);

  /// The API wraps each result, e.g. data: { trip: {...} }.
  Map<String, dynamic> _data(ApiResponse r) => r.data as Map<String, dynamic>;
  List<dynamic> _list(ApiResponse r, String key) => _data(r)[key] as List<dynamic>;

  Trip _trip(ApiResponse r) => Trip.fromJson(_data(r)['trip'] as Map<String, dynamic>);

  // ---------- driver ----------
  Future<Trip> createTrip(TripDraft draft) async => _trip(await api.post('/trips', draft.toJson()));

  Future<Trip> getTrip(String id) async => _trip(await api.get('/trips/$id'));

  /// Only send the fields that changed.
  Future<Trip> updateTrip(String id, Map<String, dynamic> changes) async =>
      _trip(await api.patch('/trips/$id', changes));

  Future<List<Trip>> myTrips({String? status, int page = 1, int limit = 50}) async {
    final r = await api.get('/trips/mine', query: {
      if (status != null) 'status': status,
      'page': '$page',
      'limit': '$limit',
    });
    return _list(r, 'trips').map((t) => Trip.fromJson(t as Map<String, dynamic>)).toList();
  }

  Future<Trip> publish(String id) async => _trip(await api.post('/trips/$id/publish'));
  Future<Trip> start(String id) async => _trip(await api.post('/trips/$id/start'));
  Future<Trip> complete(String id) async => _trip(await api.post('/trips/$id/complete'));
  Future<Trip> cancel(String id, String reason) async =>
      _trip(await api.post('/trips/$id/cancel', {'reason': reason}));

  // ---------- saved routes ----------
  Future<List<SavedRoute>> savedRoutes() async {
    final r = await api.get('/saved-routes');
    return _list(r, 'savedRoutes').map((s) => SavedRoute.fromJson(s as Map<String, dynamic>)).toList();
  }

  Future<SavedRoute> createSavedRoute(String name, List<TripStop> stops) async {
    final r = await api.post('/saved-routes', {
      'name': name,
      'stops': stops.map((s) => {'name': s.name, 'lat': s.lat, 'lng': s.lng}).toList(),
    });
    return SavedRoute.fromJson(_data(r)['savedRoute'] as Map<String, dynamic>);
  }

  Future<void> deleteSavedRoute(String id) async {
    await api.delete('/saved-routes/$id');
  }

  // ---------- passenger ----------
  Future<SearchPage> search(SearchQuery query) async {
    final r = await api.get('/trips/search', query: query.toQuery());
    final items = _list(r, 'results')
        .map((t) => TripSearchResult.fromJson(t as Map<String, dynamic>))
        .toList();
    return SearchPage(
      items: items,
      total: (r.meta['total'] as int?) ?? items.length,
      radiusKm: ((r.meta['radiusKm'] as num?) ?? 5).toDouble(),
    );
  }

  Future<SegmentAvailability> availability(String tripId, int fromStop, int toStop) async {
    final r = await api.get('/trips/$tripId/availability', query: {
      'fromStop': '$fromStop',
      'toStop': '$toStop',
    });
    return SegmentAvailability.fromJson(_data(r)['availability'] as Map<String, dynamic>);
  }
}
