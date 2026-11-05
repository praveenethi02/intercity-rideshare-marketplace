import 'package:flutter/material.dart';

import '../../../../core/api_client.dart';
import '../../../../core/app_services.dart';
import '../../../../core/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../models/trip.dart';
import '../../widgets/trip_widgets.dart';
import 'active_trip_screen.dart';
import 'edit_trip_screen.dart';
import 'saved_route_form_screen.dart';

/// Driver's view of one trip with lifecycle actions.
class DriverTripDetailScreen extends StatefulWidget {
  final String tripId;
  const DriverTripDetailScreen({super.key, required this.tripId});

  @override
  State<DriverTripDetailScreen> createState() => _DriverTripDetailScreenState();
}

class _DriverTripDetailScreenState extends State<DriverTripDetailScreen> {
  Trip? _trip;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_error != null) setState(() => _error = null);
    try {
      final trip = await AppServices.of(context).trips.getTrip(widget.tripId);
      if (mounted) setState(() => _trip = trip);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Runs an action that returns the updated trip.
  Future<void> _run(Future<Trip> Function() action, String doneMessage) async {
    setState(() => _busy = true);
    try {
      final trip = await action();
      if (!mounted) return;
      setState(() => _trip = trip);
      showSnack(context, doneMessage);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish(Trip t) async {
    final ok = await confirmDialog(
      context,
      title: 'Publish trip?',
      message: 'Passengers will be able to find and ${t.pricingMode == PricingMode.auction ? 'bid on' : 'book'} your seats.',
      confirmLabel: 'Publish',
    );
    if (ok && mounted) await _run(() => AppServices.of(context).trips.publish(t.id), 'Trip published');
  }

  Future<void> _start(Trip t) async {
    if (!t.canStartAt(DateTime.now())) {
      final opens = t.departureTime.subtract(const Duration(minutes: 30));
      showSnack(context, 'You can start from ${formatTime(opens)} (30 minutes before departure).');
      return;
    }
    final repo = AppServices.of(context).trips;
    await _run(() => repo.start(t.id), 'Trip started. Drive safe!');
    if (!mounted || _trip?.status != TripStatus.inProgress) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ActiveTripScreen(tripId: t.id)));
  }

  Future<void> _cancel(Trip t) async {
    final reason = await showCancelTripDialog(context);
    if (reason != null && mounted) await _run(() => AppServices.of(context).trips.cancel(t.id, reason), 'Trip cancelled');
  }

  Future<void> _edit(Trip t) async {
    final updated = await Navigator.of(context).push<Trip>(MaterialPageRoute(builder: (_) => EditTripScreen(trip: t)));
    if (updated != null && mounted) setState(() => _trip = updated);
  }

  void _saveAsRoute(Trip t) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SavedRouteFormScreen(initialStops: t.stops, initialName: t.routeLabel),
    ));
  }

  List<Widget> _actions(Trip t) {
    final repoBusy = _busy;
    switch (t.status) {
      case TripStatus.draft:
        return [
          BusyButton(busy: repoBusy, onPressed: () => _publish(t), label: 'Publish', icon: Icons.public),
          OutlinedButton.icon(onPressed: repoBusy ? null : () => _edit(t), icon: const Icon(Icons.edit), label: const Text('Edit')),
          TextButton(onPressed: repoBusy ? null : () => _cancel(t), child: const Text('Cancel trip')),
        ];
      case TripStatus.scheduled:
        return [
          BusyButton(busy: repoBusy, onPressed: () => _start(t), label: 'Start trip', icon: Icons.play_arrow),
          OutlinedButton.icon(onPressed: repoBusy ? null : () => _edit(t), icon: const Icon(Icons.edit), label: const Text('Edit')),
          TextButton(onPressed: repoBusy ? null : () => _cancel(t), child: const Text('Cancel trip')),
        ];
      case TripStatus.inProgress:
        return [
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => ActiveTripScreen(tripId: t.id)),
            ),
            icon: const Icon(Icons.navigation),
            label: const Text('Open active trip'),
          ),
        ];
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _trip;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip'),
        actions: [
          if (t != null && t.stops.length >= 2)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'save') _saveAsRoute(t);
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'save', child: Text('Save route as template'))],
            ),
        ],
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : t == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Row(children: [
                      Expanded(child: Text(t.routeLabel, style: Theme.of(context).textTheme.headlineSmall)),
                      TripStatusChip(t.status),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      TagChip(PricingMode.label(t.pricingMode),
                          icon: t.pricingMode == PricingMode.auction ? Icons.gavel : Icons.sell),
                      TagChip(formatKm(t.totalDistanceKm), icon: Icons.route),
                      if (t.allowsCargo) TagChip('Cargo ${t.cargoCapacityKg?.round() ?? ''} kg', icon: Icons.inventory_2),
                    ]),
                    if (t.status == TripStatus.cancelled && t.cancelReason != null)
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        margin: const EdgeInsets.only(top: 12),
                        child: ListTile(leading: const Icon(Icons.cancel), title: Text('Cancelled: ${t.cancelReason}')),
                      ),
                    const SectionTitle('Details'),
                    InfoRow(icon: Icons.schedule, label: 'Departure', value: formatDateTime(t.departureTime)),
                    if (t.estArrivalTime != null)
                      InfoRow(icon: Icons.flag_outlined, label: 'Est. arrival', value: formatDateTime(t.estArrivalTime!)),
                    InfoRow(
                      icon: Icons.payments_outlined,
                      label: t.pricingMode == PricingMode.auction ? 'Starting bid (full route)' : 'Seat price (full route)',
                      value: formatLkr(t.basePriceCents),
                    ),
                    InfoRow(
                      icon: Icons.event_seat,
                      label: 'Seats free (full route)',
                      value: '${t.seatsAvailableFullRoute ?? t.seatsOffered} of ${t.seatsOffered}',
                    ),
                    if (t.notes != null && t.notes!.isNotEmpty) InfoRow(icon: Icons.notes, label: 'Notes', value: t.notes!),
                    const SectionTitle('Route'),
                    RouteTimeline(stops: t.stops),
                    if (t.legs.isNotEmpty) ...[
                      const SectionTitle('Seats taken on each part of the route'),
                      LegOccupancy(trip: t),
                    ],
                    const SizedBox(height: 24),
                    Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: _actions(t)),
                    if (t.status == TripStatus.scheduled && t.hasReservations)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Seats are reserved, so only arrival time and notes can be changed.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 24),
                  ]),
                ),
    );
  }
}
