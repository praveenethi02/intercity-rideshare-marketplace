import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/booking_models.dart';

/// The status text and colour of a booking, shared by My bookings and the booking details.
(String, StatusTone) bookingStatus(Booking booking) {
  if (booking.isCancelled) return ('Cancelled', StatusTone.danger);
  return switch (booking.tripStatus) {
    'IN_PROGRESS' => ('On the way', StatusTone.warning),
    'COMPLETED' => ('Completed', StatusTone.neutral),
    'CANCELLED' => ('Trip cancelled', StatusTone.danger),
    _ => ('Confirmed', StatusTone.success),
  };
}

class BookingStatusBadge extends StatelessWidget {
  final Booking booking;
  const BookingStatusBadge(this.booking, {super.key});

  @override
  Widget build(BuildContext context) {
    final (label, tone) = bookingStatus(booking);
    return AppBadge(label, tone: tone);
  }
}

/// Asks before cancelling. True when the passenger agrees.
Future<bool> confirmCancelBooking(BuildContext context, Booking booking) => confirmDialog(
      context,
      title: 'Cancel booking ${booking.reference}?',
      message: 'Your ${booking.seats == 1 ? 'seat goes' : '${booking.seats} seats go'} back to the driver '
          'for other passengers.',
      confirmLabel: 'Cancel booking',
      destructive: true,
    );
