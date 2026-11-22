import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/booking_api.dart';
import '../data/booking_models.dart';

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

  Future<void> _cancel(Booking booking) async {
    final ok = await confirmDialog(
      context,
      title: 'Cancel booking ${booking.reference}?',
      message: 'Your ${booking.seats == 1 ? 'seat goes' : '${booking.seats} seats go'} back to the driver '
          'for other passengers.',
      confirmLabel: 'Cancel booking',
      destructive: true,
    );
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
            itemBuilder: (_, i) => _BookingCard(booking: bookings[i], onCancel: () => _cancel(bookings[i])),
          ),
        );
      },
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback onCancel;
  const _BookingCard({required this.booking, required this.onCancel});

  (String, StatusTone) get _status {
    if (booking.isCancelled) return ('Cancelled', StatusTone.danger);
    return switch (booking.tripStatus) {
      'IN_PROGRESS' => ('On the way', StatusTone.warning),
      'COMPLETED' => ('Completed', StatusTone.neutral),
      'CANCELLED' => ('Trip cancelled', StatusTone.danger),
      _ => ('Confirmed', StatusTone.success),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, tone) = _status;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(booking.reference, style: theme.textTheme.titleSmall)),
          AppBadge(label, tone: tone),
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