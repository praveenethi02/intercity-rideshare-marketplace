import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/driver_repository.dart';
import '../models/driver_models.dart';

/// SCRUM-45: earnings summary. Amounts stay at zero until the payments module exists.
class DriverEarningsScreen extends StatefulWidget {
  final DriverRepository repository;
  const DriverEarningsScreen({super.key, required this.repository});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  DateTimeRange? _range;
  late Future<DriverEarnings> _future = _load();

  Future<DriverEarnings> _load() {
    final range = _range;
    return widget.repository.earnings(
      from: range == null ? null : isoDate(range.start),
      to: range == null ? null : isoDate(range.end),
    );
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _range,
    );
    if (picked == null) return;
    _range = picked;
    _reload();
  }

  void _clearRange() {
    _range = null;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: FutureBuilder<DriverEarnings>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          final e = snap.data!;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(
                child: Text(
                  range == null ? 'All time' : '${formatDate(range.start)} to ${formatDate(range.end)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (range != null) TextButton(onPressed: _clearRange, child: const Text('Clear')),
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range),
                label: const Text('Dates'),
              ),
            ]),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  InfoRow(icon: Icons.event_seat_outlined, label: 'Seat earnings', value: formatLkr(e.seatEarnings)),
                  InfoRow(icon: Icons.inventory_2_outlined, label: 'Cargo earnings', value: formatLkr(e.cargoEarnings)),
                  InfoRow(icon: Icons.percent, label: 'Platform fees', value: formatLkr(e.platformFees)),
                  const Divider(),
                  InfoRow(icon: Icons.account_balance_outlined, label: 'Paid out', value: formatLkr(e.paidOut)),
                  InfoRow(icon: Icons.schedule, label: 'Pending payout', value: formatLkr(e.pendingPayout)),
                  const Divider(),
                  InfoRow(icon: Icons.flag_outlined, label: 'Completed trips', value: '${e.completedTrips}'),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Amounts will appear here once payments are available.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]);
        },
      ),
    );
  }
}
