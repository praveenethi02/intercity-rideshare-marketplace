import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/formatters.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../trips/widgets/search_result_card.dart' show fitBadge;
import '../data/booking_api.dart';
import '../data/booking_models.dart';
import '../widgets/booking_widgets.dart';
import 'booking_details_screen.dart';

/// The passenger's bookings (SCRUM-79, 80, 304): upcoming and past, and cancelling.
class MyBookingsScreen extends StatelessWidget {
  final BookingApi api;
  const MyBookingsScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My bookings'),
          bottom: const TabBar(tabs: [Tab(text: 'Upcoming'), Tab(text: 'Past')]),
        ),
        body: TabBarView(children: [
          _BookingList(api: api, when: BookingWhen.upcoming),
          _BookingList(api: api, when: BookingWhen.past),
        ]),
      ),
    );
  }
}

class _BookingList extends StatefulWidget {
  final BookingApi api;
  final BookingWhen when;
  const _BookingList({required this.api, required this.when});

  @override
  State<_BookingList> createState() => _BookingListState();
}

class _BookingListState extends State<_BookingList> {
  late Future<List<Booking>> _future = widget.api.mine(widget.when);

  Future<void> _reload() async {
    final future = widget.api.mine(widget.when);
    setState(() {
      _future = future;
    });
    await future.then((_) {}, onError: (_) {});
  }

  Future<void> _open(Booking booking) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => BookingDetailsScreen(api: widget.api, bookingId: booking.id)),
    );
    // The booking may have been cancelled there.
    if (mounted) await _reload();
  }

  Future<void> _cancel(Booking booking) async {
    final ok = await confirmCancelBooking(context, booking);
    if (!ok || !mounted) return;
    try {
      await widget.api.cancel(booking.id);
      if (!mounted) return;
      showSnack(context, 'Booking cancelled');
      await _reload();
    } catch (e) {
      if (mounted) showSnack(context, e is ApiException ? e.message : '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Booking>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SkeletonList();
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
        final bookings = snap.data!;
        if (bookings.isEmpty) {
          return EmptyView(
            icon: Icons.event_seat_outlined,
            message: widget.when == BookingWhen.upcoming
                ? 'No upcoming bookings.\nFind a ride to book a seat.'
                : 'No past bookings yet.',
          );
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.separated(
            padding: AppSpacing.screen,
            itemCount: bookings.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) => _BookingCard(
              booking: bookings[i],
              onTap: () => _open(bookings[i]),
              onCancel: () => _cancel(bookings[i]),
            ),
          ),
        );
      },
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  const _BookingCard({required this.booking, required this.onTap, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(booking.reference, style: theme.textTheme.titleSmall)),
          Expanded(child: Align(alignment: Alignment.centerRight, child: fitBadge(BookingStatusBadge(booking)))),
        ]),
        const SizedBox(height: AppSpacing.md),
        Text('${booking.pickup.name} → ${booking.drop.name}', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          formatDateTime(booking.departureTime),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${booking.seats} ${booking.seats == 1 ? 'seat' : 'seats'} · ${formatLkr(booking.totalCents)}',
          style: theme.textTheme.bodyMedium,
        ),
        if (booking.canCancel) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close),
              label: const Text('Cancel booking'),
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            ),
          ),
        ],
      ]),
    );
  }
}
