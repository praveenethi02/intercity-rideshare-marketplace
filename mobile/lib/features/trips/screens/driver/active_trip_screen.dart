import 'package:flutter/material.dart';

import '../../../../core/api_client.dart';
import '../../../../core/app_services.dart';
import '../../../../core/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../models/trip.dart';
import '../../widgets/trip_widgets.dart';

/// Shown while a trip is IN_PROGRESS. The driver ticks off stops and
/// completes the trip at the end.
///
/// Stop progress is kept on the phone for now. The GPS tracking module
/// (sprint 4) can replace [_currentStop] with the live position.
class ActiveTripScreen extends StatefulWidget {
  final String tripId;
  const ActiveTripScreen({super.key, required this.tripId});

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  Trip? _trip;
  Object? _error;
  int _currentStop = 0;
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

  Future<void> _complete(Trip t) async {
    final early = _currentStop < t.stops.length - 1;
    final ok = await confirmDialog(
      context,
      title: 'Complete trip?',
      message: early
          ? 'You have not reached ${t.destination} yet. Complete the trip anyway?'
          : 'Mark this trip as completed. Passengers will be asked to rate the ride.',
      confirmLabel: 'Complete',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await AppServices.of(context).trips.complete(t.id);
      if (!mounted) return;
      setState(() => _trip = updated);
      showSnack(context, 'Trip completed');
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _trip;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Active trip')),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : t == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Container(
                    width: double.infinity,
                    color: theme.colorScheme.tertiaryContainer,
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.routeLabel, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        _currentStop < t.stops.length - 1
                            ? 'Next stop: ${t.stops[_currentStop + 1].name}'
                            : 'Arrived at ${t.destination}',
                        style: theme.textTheme.bodyLarge,
                      ),
                      Text('Departed ${formatTime(t.departureTime)} · ${formatKm(t.totalDistanceKm)}'),
                    ]),
                  ),
                  if (t.status != TripStatus.inProgress)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        TripStatusChip(t.status),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('This trip is not in progress.')),
                      ]),
                    ),
                  Expanded(
                    child: ListView(padding: const EdgeInsets.all(16), children: [
                      RouteTimeline(
                        stops: t.stops,
                        currentStop: _currentStop,
                        onStopTap: (i) => setState(() => _currentStop = i),
                      ),
                      const SizedBox(height: 8),
                      Text('Tap a stop to mark where you are.', style: theme.textTheme.bodySmall),
                    ]),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _currentStop < t.stops.length - 1
                                ? () => setState(() => _currentStop++)
                                : null,
                            icon: const Icon(Icons.where_to_vote),
                            label: const Text('Arrived at next stop'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: BusyButton(
                            busy: _busy,
                            onPressed: t.status == TripStatus.inProgress ? () => _complete(t) : null,
                            label: 'Complete trip',
                          ),
                        ),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}
