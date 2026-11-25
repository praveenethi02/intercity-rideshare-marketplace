import 'package:flutter/material.dart';

import '../../../../core/app_services.dart';
import '../../../../core/formatters.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../models/search.dart';
import '../../models/trip.dart';
import '../../widgets/driver_vehicle_card.dart';
import '../../widgets/search_result_card.dart';
import '../../widgets/trip_widgets.dart';

/// Passenger's view of a trip for their own segment (pickup → drop): seats left on each leg,
/// cargo space, times, price, driver and vehicle (SCRUM-70, SCRUM-71, SCRUM-73, SCRUM-74).
/// The Book / Bid button hands a [SegmentSelection] to the Booking or
/// Auction module via [AppServices.onBookSegment].
class PassengerTripDetailScreen extends StatefulWidget {
  final String tripId;
  final int fromStop;
  final int toStop;
  final int seats;

  const PassengerTripDetailScreen({
    super.key,
    required this.tripId,
    required this.fromStop,
    required this.toStop,
    this.seats = 1,
  });

  @override
  State<PassengerTripDetailScreen> createState() => _PassengerTripDetailScreenState();
}

class _PassengerTripDetailScreenState extends State<PassengerTripDetailScreen> {
  late Future<(Trip, SegmentAvailability)> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<(Trip, SegmentAvailability)> _fetch() async {
    final repo = AppServices.of(context).trips;
    final trip = repo.getTrip(widget.tripId);
    final availability = repo.availability(widget.tripId, widget.fromStop, widget.toStop);
    final Trip loaded;
    try {
      loaded = await trip;
    } catch (_) {
      availability.ignore(); // only the first error is shown
      rethrow;
    }
    return (loaded, await availability);
  }

  Future<void> _reload() async {
    final f = _fetch();
    setState(() {
      _future = f;
    });
    try {
      await f;
    } catch (_) {}
  }

  Future<void> _book(Trip trip, SegmentAvailability a) async {
    final services = AppServices.of(context);
    final selection = SegmentSelection(
      tripId: trip.id,
      fromStop: widget.fromStop,
      toStop: widget.toStop,
      seats: widget.seats,
      pricingMode: trip.pricingMode,
      pricePerSeatCents: a.segmentPriceCents,
    );
    final handler = services.onBookSegment;
    if (handler == null) {
      showSnack(context, 'Booking and bidding screens are added by the Booking/Auction modules.');
      return;
    }
    await handler(context, selection);
    if (mounted) _reload(); // seats may have changed
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride details')),
      body: FutureBuilder<(Trip, SegmentAvailability)>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const SkeletonList(count: 4);
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          final (trip, a) = snap.data!;
          return _body(trip, a);
        },
      ),
    );
  }

  /// Free seats on each leg of the passenger's part. Older servers send no legs with the
  /// availability, so they are taken from the trip then.
  List<SegmentLeg> _legs(Trip trip, SegmentAvailability a) {
    if (a.legs.isNotEmpty) return a.legs;
    return [
      for (final leg in trip.legs)
        if (leg.legIndex >= widget.fromStop && leg.legIndex < widget.toStop && leg.legIndex + 1 < trip.stops.length)
          SegmentLeg(
            legIndex: leg.legIndex,
            fromName: trip.stops[leg.legIndex].name,
            toName: trip.stops[leg.legIndex + 1].name,
            seatsAvailable: leg.seatsAvailable,
          ),
    ];
  }

  Widget _body(Trip trip, SegmentAvailability a) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final pickup = trip.stops[widget.fromStop];
    final drop = trip.stops[widget.toStop];
    final km = (drop.kmFromStart ?? 0) - (pickup.kmFromStart ?? 0);
    final isAuction = trip.pricingMode == PricingMode.auction;
    final bookable = trip.status == TripStatus.scheduled && a.seatsAvailable >= widget.seats;
    final seatsOffered = a.seatsOffered ?? trip.seatsOffered;
    final allowsCargo = a.allowsCargo ?? trip.allowsCargo;
    final cargoKg = a.cargoCapacityKg ?? trip.cargoCapacityKg;
    // The drop stop's own time, or the trip's arrival when the passenger rides to the end.
    final isLastStop = widget.toStop == trip.stops.length - 1;
    final dropTime = drop.plannedTime ?? (isLastStop ? trip.estArrivalTime : null);
    final legs = _legs(trip, a);

    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
              // Pull to refresh must work even when the details fit on the screen.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.screen,
              children: [
                Text('${pickup.name} → ${drop.name}', style: theme.textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text('Part of ${trip.routeLabel}', style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.sm),
                Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                  fitBadge(AppBadge(
                    PricingMode.label(trip.pricingMode),
                    tone: StatusTone.info,
                    icon: isAuction ? Icons.gavel : Icons.sell,
                  )),
                  fitBadge(AppBadge(formatKm(km), icon: Icons.route)),
                  if (allowsCargo) fitBadge(const AppBadge('Takes cargo', icon: Icons.inventory_2_outlined)),
                  if (trip.status != TripStatus.scheduled) TripStatusChip(trip.status),
                ]),
                const SectionTitle('Your ride'),
                AppCard(
                  child: Column(children: [
                    InfoRow(
                      icon: Icons.schedule,
                      label: 'Pickup time',
                      value: formatDateTime(pickup.plannedTime ?? trip.departureTime),
                    ),
                    InfoRow(
                      icon: Icons.flag_outlined,
                      label: drop.plannedTime == null ? 'Arrival (estimate)' : 'Drop time',
                      value: dropTime == null ? 'Not given' : formatDateTime(dropTime),
                    ),
                    InfoRow(icon: Icons.route, label: 'Distance', value: formatKm(km)),
                    InfoRow(
                      icon: Icons.payments_outlined,
                      label: isAuction ? 'Starting bid per seat' : 'Price per seat',
                      value: formatLkr(a.segmentPriceCents),
                    ),
                    if (!isAuction)
                      InfoRow(
                        icon: Icons.calculate_outlined,
                        label: 'Total for ${widget.seats} seat${widget.seats > 1 ? 's' : ''}',
                        value: formatLkr(a.segmentPriceCents * widget.seats),
                      ),
                  ]),
                ),
                const SectionTitle('Driver and vehicle'),
                DriverVehicleCard(
                  loadDriver: () => AppServices.of(context).trips.driverProfile(trip.driverId),
                  vehicle: trip.vehicle,
                ),
                const SectionTitle('Seats'),
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          '${seatsLeftLabel(a.seatsAvailable, seatsOffered)} on your part',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: fitBadge(AppBadge(
                            a.seatsAvailable >= widget.seats ? 'Enough for you' : 'Not enough',
                            tone: a.seatsAvailable >= widget.seats ? StatusTone.success : StatusTone.danger,
                          )),
                        ),
                      ),
                    ]),
                    if (legs.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text('Free seats on each part of your ride', style: muted),
                      for (final leg in legs)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Row(children: [
                            Expanded(child: Text('${leg.fromName} → ${leg.toName}')),
                            const SizedBox(width: AppSpacing.sm),
                            AppBadge(
                              '${leg.seatsAvailable} free',
                              tone: leg.seatsAvailable == 0 ? StatusTone.danger : StatusTone.neutral,
                              icon: Icons.event_seat,
                            ),
                          ]),
                        ),
                    ],
                  ]),
                ),
                if (allowsCargo) ...[
                  const SectionTitle('Cargo'),
                  AppCard(
                    child: InfoRow(
                      icon: Icons.inventory_2_outlined,
                      label: 'Cargo space',
                      value: cargoKg == null ? 'Ask the driver' : 'Up to ${formatKg(cargoKg)}',
                    ),
                  ),
                ],
                if (trip.notes != null && trip.notes!.isNotEmpty) ...[
                  const SectionTitle('Driver notes'),
                  AppCard(child: Text(trip.notes!)),
                ],
                if (isAuction)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: AppCard(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.info_outline, color: theme.colorScheme.primary),
                        const SizedBox(width: AppSpacing.md),
                        const Expanded(
                          child: Text('This trip uses a seat auction. Place a bid; the highest bids win the seats '
                              'when the auction closes.'),
                        ),
                      ]),
                    ),
                  ),
                const SectionTitle('Route'),
                RouteTimeline(stops: trip.stops, highlightFrom: widget.fromStop, highlightTo: widget.toStop),
              ]),
        ),
      ),
      SafeArea(
        child: Padding(
          padding: AppSpacing.screen,
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: bookable ? () => _book(trip, a) : null,
              icon: Icon(isAuction ? Icons.gavel : Icons.event_seat),
              label: Text(
                !bookable
                    ? (trip.status != TripStatus.scheduled ? 'Not available' : 'Not enough seats')
                    : isAuction
                        ? 'Place a bid'
                        : 'Book ${widget.seats} seat${widget.seats > 1 ? 's' : ''} · '
                            '${formatLkr(a.segmentPriceCents * widget.seats)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
