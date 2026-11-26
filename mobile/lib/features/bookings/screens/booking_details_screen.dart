import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/formatters.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../trips/models/trip.dart';
import '../../trips/widgets/driver_vehicle_card.dart';
import '../../trips/widgets/search_result_card.dart' show fitBadge;
import '../../trips/widgets/trip_widgets.dart';
import '../data/booking_api.dart';
import '../data/booking_models.dart';
import '../widgets/booking_widgets.dart';

/// One booking with its whole journey (SCRUM-83): status, stops, price, driver and vehicle.
class BookingDetailsScreen extends StatefulWidget {
  final BookingApi api;
  final String bookingId;
  const BookingDetailsScreen({super.key, required this.api, required this.bookingId});

  @override
  State<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends State<BookingDetailsScreen> {
  late Future<Booking> _future = widget.api.get(widget.bookingId);
  bool _cancelling = false;

  Future<void> _reload() async {
    final future = widget.api.get(widget.bookingId);
    setState(() {
      _future = future;
    });
    await future.then((_) {}, onError: (_) {});
  }

  Future<void> _cancel(Booking booking) async {
    final ok = await confirmCancelBooking(context, booking);
    if (!ok || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await widget.api.cancel(booking.id);
      if (!mounted) return;
      showSnack(context, 'Booking cancelled');
      await _reload();
    } catch (e) {
      if (mounted) showSnack(context, e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Booking details')),
      body: FutureBuilder<Booking>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const SkeletonList(count: 4);
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          return RefreshIndicator(onRefresh: _reload, child: _body(snap.data!));
        },
      ),
    );
  }

  Widget _body(Booking b) {
    final theme = Theme.of(context);
    final stops = _timelineStops(b);
    final driverId = b.driverId;
    return ListView(
      // Pull to refresh must work even when the details fit on the screen.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.screen,
      children: [
        SelectableText(b.reference, style: theme.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        fitBadge(BookingStatusBadge(b)),
        const SizedBox(height: AppSpacing.md),
        Text('${b.pickup.name} → ${b.drop.name}', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text('Part of ${b.originName} → ${b.destinationName}', style: theme.textTheme.bodyMedium),
        if (b.cancelReason != null || b.tripCancelReason != null) ...[
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(children: [
              if (b.cancelReason != null)
                InfoRow(icon: Icons.info_outline, label: 'Your cancel reason', value: b.cancelReason!),
              if (b.tripCancelReason != null)
                InfoRow(icon: Icons.info_outline, label: 'Why the trip was cancelled', value: b.tripCancelReason!),
            ]),
          ),
        ],
        const SectionTitle('Your journey'),
        AppCard(
          child: Column(children: [
            InfoRow(icon: Icons.event, label: 'Trip departure', value: formatDateTime(b.departureTime)),
            InfoRow(icon: Icons.trip_origin, label: 'Pickup', value: b.pickup.name),
            InfoRow(icon: Icons.schedule, label: 'Pickup time', value: _time(b.pickup)),
            InfoRow(icon: Icons.place, label: 'Drop', value: b.drop.name),
            InfoRow(icon: Icons.schedule, label: 'Drop time', value: _time(b.drop)),
            if (b.startedAt != null)
              InfoRow(icon: Icons.play_arrow_outlined, label: 'Started', value: formatDateTime(b.startedAt!)),
            if (b.completedAt != null)
              InfoRow(icon: Icons.flag_outlined, label: 'Completed', value: formatDateTime(b.completedAt!)),
          ]),
        ),
        const SectionTitle('Stops'),
        RouteTimeline(stops: stops, highlightFrom: 0, highlightTo: stops.length - 1),
        const SectionTitle('Seats and price'),
        AppCard(
          child: Column(children: [
            InfoRow(icon: Icons.event_seat, label: 'Seats', value: '${b.seats}'),
            InfoRow(icon: Icons.sell_outlined, label: 'Price per seat', value: formatLkr(b.pricePerSeatCents)),
            InfoRow(icon: Icons.payments_outlined, label: 'Total', value: formatLkr(b.totalCents)),
          ]),
        ),
        if (driverId != null) ...[
          const SectionTitle('Driver and vehicle'),
          DriverVehicleCard(loadDriver: () => widget.api.driverProfile(driverId), vehicle: b.vehicle),
        ],
        if (b.canCancel) ...[
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            onPressed: _cancelling ? null : () => _cancel(b),
            icon: const Icon(Icons.close),
            label: const Text('Cancel booking'),
            style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }

  String _time(BookingStop stop) => stop.plannedTime == null ? 'Not given' : formatDateTime(stop.plannedTime!);

  /// The stops for [RouteTimeline], which shows only names and times. Bookings have no coordinates.
  List<TripStop> _timelineStops(Booking b) => [
        for (final s in b.stops.length >= 2 ? b.stops : [b.pickup, b.drop])
          TripStop(order: s.order, name: s.name, lat: 0, lng: 0, plannedTime: s.plannedTime),
      ];
}
