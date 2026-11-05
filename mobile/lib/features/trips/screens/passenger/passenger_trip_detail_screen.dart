import 'package:flutter/material.dart';

import '../../../../core/app_services.dart';
import '../../../../core/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../models/search.dart';
import '../../models/trip.dart';
import '../../widgets/trip_widgets.dart';

/// Passenger's view of a trip for their own segment (pickup → drop).
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
    return (await trip, await availability);
  }

  Future<void> _reload() async {
    final f = _fetch();
    setState(() => _future = f);
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
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          final (trip, a) = snap.data!;
          return _body(trip, a);
        },
      ),
    );
  }

  Widget _body(Trip trip, SegmentAvailability a) {
    final theme = Theme.of(context);
    final pickup = trip.stops[widget.fromStop];
    final drop = trip.stops[widget.toStop];
    final km = (drop.kmFromStart ?? 0) - (pickup.kmFromStart ?? 0);
    final isAuction = trip.pricingMode == PricingMode.auction;
    final bookable = trip.status == TripStatus.scheduled && a.seatsAvailable >= widget.seats;

    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('${pickup.name} → ${drop.name}', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Part of ${trip.routeLabel}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              TagChip(PricingMode.label(trip.pricingMode), icon: isAuction ? Icons.gavel : Icons.sell),
              TagChip(formatKm(km), icon: Icons.route),
              if (trip.allowsCargo) const TagChip('Takes cargo', icon: Icons.inventory_2),
              if (trip.status != TripStatus.scheduled) TripStatusChip(trip.status),
            ]),
            const SectionTitle('Your ride'),
            InfoRow(
              icon: Icons.schedule,
              label: 'Pickup time',
              value: formatDateTime(pickup.plannedTime ?? trip.departureTime),
            ),
            if (drop.plannedTime != null)
              InfoRow(icon: Icons.flag_outlined, label: 'Drop time', value: formatDateTime(drop.plannedTime!)),
            InfoRow(
              icon: Icons.payments_outlined,
              label: isAuction ? 'Starting bid per seat' : 'Price per seat',
              value: formatLkr(a.segmentPriceCents),
            ),
            if (!isAuction && widget.seats > 1)
              InfoRow(
                icon: Icons.calculate_outlined,
                label: 'Total for ${widget.seats} seats',
                value: formatLkr(a.segmentPriceCents * widget.seats),
              ),
            InfoRow(icon: Icons.event_seat, label: 'Seats left on your part', value: '${a.seatsAvailable}'),
            if (trip.notes != null && trip.notes!.isNotEmpty)
              InfoRow(icon: Icons.notes, label: 'Driver notes', value: trip.notes!),
            if (isAuction)
              const Card(
                margin: EdgeInsets.only(top: 12),
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('This trip uses a seat auction'),
                  subtitle: Text('Place a bid. The highest bids win the seats when the auction closes.'),
                ),
              ),
            const SectionTitle('Route'),
            RouteTimeline(stops: trip.stops, highlightFrom: widget.fromStop, highlightTo: widget.toStop),
          ]),
        ),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                        : 'Book ${widget.seats} seat${widget.seats > 1 ? 's' : ''} · ${formatLkr(a.segmentPriceCents * widget.seats)}',
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
