import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/booking_api.dart';
import '../data/booking_models.dart';
import 'booking_details_screen.dart';
import 'my_bookings_screen.dart';

/// Step 2 of booking (SCRUM-304): the booking is confirmed, with its reference.
class BookingSuccessScreen extends StatelessWidget {
  final BookingApi api;
  final Booking booking;
  const BookingSuccessScreen({super.key, required this.api, required this.booking});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          const Center(child: StateIcon(Icons.check_circle_outline, tone: StatusTone.success)),
          const SizedBox(height: AppSpacing.lg),
          Text('Booking confirmed', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Show this reference to your driver.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            child: Column(children: [
              Text('Booking reference', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                booking.reference,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(children: [
              InfoRow(icon: Icons.trip_origin, label: 'Pickup', value: booking.pickup.name),
              InfoRow(icon: Icons.place, label: 'Drop', value: booking.drop.name),
              InfoRow(icon: Icons.event, label: 'Departure', value: formatDateTime(booking.departureTime)),
              InfoRow(icon: Icons.event_seat, label: 'Seats', value: '${booking.seats}'),
              InfoRow(icon: Icons.payments_outlined, label: 'Total', value: formatLkr(booking.totalCents)),
            ]),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => MyBookingsScreen(api: api)),
            ),
            child: const Text('View my bookings'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => BookingDetailsScreen(api: api, bookingId: booking.id)),
            ),
            child: const Text('View details'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ],
      ),
    );
  }
}
