import '../../../core/api_client.dart';

/// Someone the signed-in user can still rate on a completed trip.
class PendingRating {
  final String tripId;
  final String route;
  final DateTime departureTime;
  final String rateeId;
  final String rateeName;
  final bool rateeIsDriver;

  const PendingRating({
    required this.tripId,
    required this.route,
    required this.departureTime,
    required this.rateeId,
    required this.rateeName,
    required this.rateeIsDriver,
  });

  factory PendingRating.fromJson(Map<String, dynamic> j) {
    final trip = j['trip'] as Map<String, dynamic>;
    final ratee = j['ratee'] as Map<String, dynamic>;
    return PendingRating(
      tripId: trip['id'] as String,
      route: '${trip['originName']} → ${trip['destinationName']}',
      departureTime: DateTime.parse(trip['departureAt'] as String).toLocal(),
      rateeId: ratee['id'] as String,
      rateeName: ratee['name'] as String,
      rateeIsDriver: ratee['role'] == 'DRIVER',
    );
  }
}

/// A rating the user received.
class ReceivedRating {
  final int stars;
  final String? review;
  final String reviewerName;
  final DateTime createdAt;

  const ReceivedRating({required this.stars, this.review, required this.reviewerName, required this.createdAt});

  factory ReceivedRating.fromJson(Map<String, dynamic> j) => ReceivedRating(
        stars: j['stars'] as int,
        review: j['review'] as String?,
        reviewerName: (j['reviewer'] as Map<String, dynamic>)['name'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      );
}

/// The average, the count and the newest ratings. [average] is null when there are none.
class RatingSummary {
  final double? average;
  final int count;
  final List<ReceivedRating> ratings;

  const RatingSummary({this.average, required this.count, required this.ratings});

  factory RatingSummary.fromJson(Map<String, dynamic> j) => RatingSummary(
        average: (j['averageRating'] as num?)?.toDouble(),
        count: j['ratingCount'] as int,
        ratings: [
          for (final r in j['ratings'] as List<dynamic>) ReceivedRating.fromJson(r as Map<String, dynamic>),
        ],
      );
}

/// Calls /api/v1/ratings. See docs/api/changes/ratings.md.
class RatingApi {
  final ApiClient api;
  const RatingApi(this.api);

  Future<List<PendingRating>> pending() async {
    final r = await api.get('/ratings/pending');
    return [
      for (final p in (r.data as Map<String, dynamic>)['pending'] as List<dynamic>)
        PendingRating.fromJson(p as Map<String, dynamic>),
    ];
  }

  Future<void> rate(PendingRating p, int stars, String review) async {
    await api.post('/ratings', {
      'tripId': p.tripId,
      'rateeId': p.rateeId,
      'stars': stars,
      if (review.isNotEmpty) 'review': review,
    });
  }

  /// The 50 newest ratings. The average covers all of them.
  Future<RatingSummary> received(String userId) async {
    final r = await api.get('/ratings/users/$userId', query: {'limit': '50'});
    return RatingSummary.fromJson(r.data as Map<String, dynamic>);
  }
}
