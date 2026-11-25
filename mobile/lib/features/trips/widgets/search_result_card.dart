import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/common_widgets.dart';
import '../models/search.dart';
import '../models/trip.dart';

/// Shrinks a badge that is wider than the space left (a 320 px screen or large text) instead of
/// letting it overflow; badges never wrap their text.
Widget fitBadge(Widget badge) => FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: badge);

/// "2 of 3 seats left", or "2 seats left" when the server did not send the seats offered.
String seatsLeftLabel(int available, int? offered) {
  final noun = (offered ?? available) == 1 ? 'seat' : 'seats';
  return offered == null ? '$available $noun left' : '$available of $offered $noun left';
}

/// 120.0 -> "120 kg", 12.5 -> "12.5 kg"
String formatKg(double kg) => kg == kg.roundToDouble() ? '${kg.round()} kg' : '${kg.toStringAsFixed(1)} kg';

/// One trip in the passenger's search results (SCRUM-67, SCRUM-74): pickup and arrival time,
/// the passenger's part of the route, price per seat, seats left and cargo space.
class TripResultCard extends StatelessWidget {
  final TripSearchResult result;
  final int seats;
  final VoidCallback onTap;
  const TripResultCard({super.key, required this.result, required this.seats, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final r = result;
    final isAuction = r.pricingMode == PricingMode.auction;
    // The drop stop's own time when the driver set one, otherwise when the whole trip ends.
    final dropTime = r.drop.plannedTime;
    final tripEnd = r.estimatedArrivalTime;
    final fewSeats = r.seatsAvailable <= 1;

    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                children: [
                  Text(formatTime(r.pickupTime), style: theme.textTheme.titleLarge),
                  if (dropTime != null)
                    Text('→ ${formatTime(dropTime)}', style: theme.textTheme.titleMedium)
                  else if (tripEnd != null)
                    Text('trip ends ~${formatTime(tripEnd)}', style: muted),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('${r.pickup.name} → ${r.drop.name}', style: theme.textTheme.titleSmall),
            ]),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              formatLkr(r.segmentPriceCents),
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
            ),
            Text(isAuction ? 'starting bid / seat' : 'per seat', style: muted),
          ]),
        ]),
        const SizedBox(height: AppSpacing.md),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
          fitBadge(AppBadge(
            seatsLeftLabel(r.seatsAvailable, r.seatsOffered),
            tone: fewSeats ? StatusTone.warning : StatusTone.success,
            icon: Icons.event_seat,
          )),
          fitBadge(AppBadge(
            PricingMode.label(r.pricingMode),
            tone: StatusTone.info,
            icon: isAuction ? Icons.gavel : Icons.sell,
          )),
          if (r.allowsCargo)
            fitBadge(AppBadge(
              r.cargoCapacityKg == null ? 'Takes cargo' : 'Cargo up to ${formatKg(r.cargoCapacityKg!)}',
              icon: Icons.inventory_2_outlined,
            )),
          fitBadge(AppBadge(formatKm(r.segmentDistanceKm), icon: Icons.route)),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Pickup ${formatKm(r.pickupDistanceKm)} from you · drop ${formatKm(r.dropDistanceKm)} from your destination',
          style: muted,
        ),
        if (!isAuction && seats > 1)
          Text('Total for $seats seats: ${formatLkr(r.segmentPriceCents * seats)}', style: muted),
      ]),
    );
  }
}
