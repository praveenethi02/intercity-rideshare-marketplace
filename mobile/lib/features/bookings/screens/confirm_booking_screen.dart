import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/app_services.dart';
import '../../../core/formatters.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../trips/models/search.dart' show SegmentSelection;
import '../../trips/models/trip.dart';
import '../data/booking_api.dart';
import 'booking_success_screen.dart';

/// Step 1 of booking (SCRUM-304): check the route, seats and price, then confirm.
class ConfirmBookingScreen extends StatefulWidget {
  final BookingApi api;
  final SegmentSelection selection;
  const ConfirmBookingScreen({super.key, required this.api, required this.selection});

  @override
  State<ConfirmBookingScreen> createState() => _ConfirmBookingScreenState();
}

class _ConfirmBookingScreenState extends State<ConfirmBookingScreen> {
  late Future<Trip> _trip;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _trip = _load();
  }

  Future<Trip> _load() => AppServices.of(context).trips.getTrip(widget.selection.tripId);

  void _reload() => setState(() {
        _trip = _load();
      });

  /// The stop with this order number, for its name and planned time.
  TripStop? _stop(Trip trip, int order) {
    for (final stop in trip.stops) {
      if (stop.order == order) return stop;
    }
    return order < trip.stops.length ? trip.stops[order] : null;
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final booking = await widget.api.create(widget.selection);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => BookingSuccessScreen(api: widget.api, booking: booking)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm booking')),
      body: FutureBuilder<Trip>(
        future: _trip,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          return _body(snap.data!);
        },
      ),
    );
  }

  Widget _body(Trip trip) {
    final theme = Theme.of(context);
    final s = widget.selection;
    final pickup = _stop(trip, s.fromStop);
    final drop = _stop(trip, s.toStop);
    final total = s.seats * s.pricePerSeatCents;

    return ListView(
      padding: AppSpacing.screen,
      children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your trip', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            _StopRow(icon: Icons.trip_origin, label: 'Pickup', name: pickup?.name ?? 'Stop ${s.fromStop}'),
            _StopRow(icon: Icons.place, label: 'Drop', name: drop?.name ?? 'Stop ${s.toStop}'),
            const Divider(height: AppSpacing.xl),
            InfoRow(icon: Icons.event, label: 'Departure', value: formatDateTime(trip.departureTime)),
          ]),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(children: [
            InfoRow(icon: Icons.event_seat, label: 'Seats', value: '${s.seats}'),
            InfoRow(icon: Icons.sell_outlined, label: 'Price per seat', value: formatLkr(s.pricePerSeatCents)),
            const Divider(height: AppSpacing.xl),
            Row(children: [
              Expanded(child: Text('Total', style: theme.textTheme.titleMedium)),
              Text(formatLkr(total), style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary)),
            ]),
          ]),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Your seats are held as soon as you confirm. You can cancel until the trip starts.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: AppSpacing.md),
        ],
        BusyButton(busy: _busy, onPressed: _confirm, label: 'Confirm booking', icon: Icons.check),
      ],
    );
  }
}

class _StopRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String name;
  const _StopRow({required this.icon, required this.label, required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.md),
        Text('$label  ', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Expanded(child: Text(name, style: theme.textTheme.titleSmall)),
      ]),
    );
  }
}