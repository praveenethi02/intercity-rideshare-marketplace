import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../models/trip.dart';

/// Coloured chip for a trip status.
class TripStatusChip extends StatelessWidget {
  final String status;
  const TripStatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      TripStatus.draft => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      TripStatus.scheduled => (scheme.primaryContainer, scheme.onPrimaryContainer),
      TripStatus.inProgress => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      TripStatus.completed => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _ => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(TripStatus.label(status), style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Small rounded label (e.g. "Seat auction", "Cargo").
class TagChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  const TagChip(this.label, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 4)],
        Text(label, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}

/// Vertical list of stops joined by a line. Legs inside
/// [highlightFrom]..[highlightTo] are drawn in the primary colour.
class RouteTimeline extends StatelessWidget {
  final List<TripStop> stops;
  final int? highlightFrom;
  final int? highlightTo;
  final int? currentStop; // for the active-trip screen
  final void Function(int index)? onStopTap;

  const RouteTimeline({
    super.key,
    required this.stops,
    this.highlightFrom,
    this.highlightTo,
    this.currentStop,
    this.onStopTap,
  });

  bool _legHighlighted(int leg) {
    if (highlightFrom == null || highlightTo == null) return true;
    return leg >= highlightFrom! && leg < highlightTo!;
  }

  bool _stopHighlighted(int i) {
    if (highlightFrom == null || highlightTo == null) return true;
    return i >= highlightFrom! && i <= highlightTo!;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Column(children: [
      for (var i = 0; i < stops.length; i++)
        InkWell(
          onTap: onStopTap == null ? null : () => onStopTap!(i),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 32,
                child: Column(children: [
                  Expanded(
                    child: Container(
                      width: 3,
                      color: i == 0
                          ? Colors.transparent
                          : (_legHighlighted(i - 1) ? scheme.primary : scheme.outlineVariant),
                    ),
                  ),
                  _dot(i, scheme),
                  Expanded(
                    child: Container(
                      width: 3,
                      color: i == stops.length - 1
                          ? Colors.transparent
                          : (_legHighlighted(i) ? scheme.primary : scheme.outlineVariant),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      stops[i].name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: _stopHighlighted(i) ? FontWeight.w600 : FontWeight.normal,
                        color: _stopHighlighted(i) ? null : scheme.outline,
                      ),
                    ),
                    if (_subtitle(i).isNotEmpty) Text(_subtitle(i), style: theme.textTheme.bodySmall),
                  ]),
                ),
              ),
              if (i == highlightFrom) const Padding(padding: EdgeInsets.all(8), child: TagChip('Pickup')),
              if (i == highlightTo) const Padding(padding: EdgeInsets.all(8), child: TagChip('Drop')),
            ]),
          ),
        ),
    ]);
  }

  String _subtitle(int i) {
    final s = stops[i];
    final parts = <String>[
      if (s.plannedTime != null) formatTime(s.plannedTime!),
      if (s.kmFromStart != null && i > 0) '${formatKm(s.kmFromStart!)} from start',
    ];
    return parts.join(' · ');
  }

  Widget _dot(int i, ColorScheme scheme) {
    final isEnd = i == 0 || i == stops.length - 1;
    final done = currentStop != null && i < currentStop!;
    final here = currentStop != null && i == currentStop;
    final color = _stopHighlighted(i) ? scheme.primary : scheme.outlineVariant;
    if (here) return Icon(Icons.directions_car, size: 22, color: scheme.tertiary);
    if (done) return Icon(Icons.check_circle, size: 18, color: scheme.primary);
    return Container(
      width: isEnd ? 16 : 12,
      height: isEnd ? 16 : 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isEnd ? color : scheme.surface,
        border: Border.all(color: color, width: 3),
      ),
    );
  }
}

/// One bar per leg showing reserved seats (driver view).
class LegOccupancy extends StatelessWidget {
  final Trip trip;
  const LegOccupancy({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (trip.legs.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      for (final leg in trip.legs)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(trip.legLabel(leg.legIndex), style: theme.textTheme.bodyMedium)),
              Text('${leg.seatsReserved}/${trip.seatsOffered} taken', style: theme.textTheme.bodySmall),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: trip.seatsOffered == 0 ? 0 : leg.seatsReserved / trip.seatsOffered,
              ),
            ),
          ]),
        ),
    ]);
  }
}

/// Card used in the driver's trip lists.
class TripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback? onTap;
  const TripCard({super.key, required this.trip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(trip.routeLabel, style: theme.textTheme.titleMedium)),
              TripStatusChip(trip.status),
            ]),
            const SizedBox(height: 6),
            Text(formatDateTime(trip.departureTime), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              TagChip(PricingMode.label(trip.pricingMode),
                  icon: trip.pricingMode == PricingMode.auction ? Icons.gavel : Icons.sell),
              TagChip('${trip.seatsOffered} seats', icon: Icons.event_seat),
              TagChip(formatLkr(trip.basePriceCents)),
              TagChip(formatKm(trip.totalDistanceKm), icon: Icons.route),
              if (trip.allowsCargo) const TagChip('Cargo', icon: Icons.inventory_2),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Asks the driver for a cancel reason. Returns null if they back out.
Future<String?> showCancelTripDialog(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _CancelTripDialog());

class _CancelTripDialog extends StatefulWidget {
  const _CancelTripDialog();
  @override
  State<_CancelTripDialog> createState() => _CancelTripDialogState();
}

class _CancelTripDialogState extends State<_CancelTripDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  static const _quickReasons = ['Vehicle breakdown', 'Personal emergency', 'Weather or road closure'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel this trip?'),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Passengers with seats will be informed and refunded under the refund policy.'),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in _quickReasons) ActionChip(label: Text(r), onPressed: () => _controller.text = r),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            controller: _controller,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Reason'),
            validator: (v) => (v == null || v.trim().length < 3) ? 'Please give a reason' : null,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep trip')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () {
            if (_formKey.currentState!.validate()) Navigator.pop(context, _controller.text.trim());
          },
          child: const Text('Cancel trip'),
        ),
      ],
    );
  }
}
