import '../../../core/api_client.dart';
import '../../trips/models/search.dart' show SegmentSelection;
import 'booking_models.dart';

/// Which bookings GET /bookings/mine returns.
enum BookingWhen { upcoming, past }

/// Calls /api/v1/bookings through the shared client, which adds the token and refreshes it.
class BookingApi {
  final ApiClient api;
  const BookingApi(this.api);

  Booking _booking(ApiResponse r) =>
      Booking.fromJson((r.data as Map<String, dynamic>)['booking'] as Map<String, dynamic>);

  /// Books seats. The server takes the price from the trip, so the app never sends one.
  Future<Booking> create(SegmentSelection s) async => _booking(await api.post('/bookings', {
        'tripId': s.tripId,
        'fromStop': s.fromStop,
        'toStop': s.toStop,
        'seats': s.seats,
      }));

  Future<List<Booking>> mine(BookingWhen when) async {
    final r = await api.get('/bookings/mine', query: {'when': when.name, 'limit': '50'});
    return ((r.data as Map<String, dynamic>)['bookings'] as List<dynamic>)
        .map((b) => Booking.fromJson(b as Map<String, dynamic>))
        .toList();
  }

  Future<Booking> cancel(String id) async => _booking(await api.post('/bookings/$id/cancel', {}));
}