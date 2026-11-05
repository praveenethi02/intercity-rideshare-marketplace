import 'package:flutter/widgets.dart';

import '../features/trips/data/trip_repository.dart';
import '../features/trips/models/search.dart';

/// Called when a passenger taps Book / Bid. The Booking and Auction members
/// set this to open their own screens.
typedef BookSegmentCallback = Future<void> Function(BuildContext context, SegmentSelection selection);

/// Gives every screen access to shared services without extra packages.
/// Put it ABOVE MaterialApp's navigator (see main.dart).
class AppServices extends InheritedWidget {
  const AppServices({
    super.key,
    required this.trips,
    this.driverVehicleId,
    this.vehicleSeatCapacity,
    this.onBookSegment,
    required super.child,
  });

  final TripRepository trips;

  /// The logged-in driver's APPROVED vehicle (from Member 3). Null for passengers.
  final String? driverVehicleId;

  /// Total seats in that vehicle including the driver's seat (from Member 3).
  final int? vehicleSeatCapacity;

  final BookSegmentCallback? onBookSegment;

  /// Most seats a driver can offer (driver's own seat is not for sale).
  int get maxSeatsToOffer {
    final capacity = vehicleSeatCapacity;
    if (capacity == null) return 14;
    return (capacity - 1).clamp(1, 14).toInt();
  }

  /// Safe to call from initState and callbacks.
  static AppServices of(BuildContext context) {
    final services = context.getInheritedWidgetOfExactType<AppServices>();
    assert(services != null, 'AppServices is missing above this widget');
    return services!;
  }

  @override
  bool updateShouldNotify(AppServices oldWidget) =>
      trips != oldWidget.trips ||
      driverVehicleId != oldWidget.driverVehicleId ||
      vehicleSeatCapacity != oldWidget.vehicleSeatCapacity ||
      onBookSegment != oldWidget.onBookSegment;
}
