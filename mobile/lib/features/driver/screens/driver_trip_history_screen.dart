import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/driver_repository.dart';
import '../models/driver_models.dart';
import '../widgets/driver_widgets.dart';

/// SCRUM-44: every trip this driver has offered, newest first, with a status filter.
class DriverTripHistoryScreen extends StatefulWidget {
  final DriverRepository repository;
  const DriverTripHistoryScreen({super.key, required this.repository});

  @override
  State<DriverTripHistoryScreen> createState() => _DriverTripHistoryScreenState();
}

const _filters = <String?, String>{
  null: 'All',
  'SCHEDULED': 'Scheduled',
  'IN_PROGRESS': 'In progress',
  'COMPLETED': 'Completed',
  'CANCELLED': 'Cancelled',
};

class _DriverTripHistoryScreenState extends State<DriverTripHistoryScreen> {
  String? _status;
  final List<DriverTripSummary> _trips = [];
  int _page = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    final status = _status;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.trips(status: status);
      if (!mounted || status != _status) return;
      setState(() {
        _trips
          ..clear()
          ..addAll(page.trips);
        _page = page.page;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted && status == _status) setState(() => _error = e);
    } finally {
      if (mounted && status == _status) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final status = _status;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.repository.trips(status: status, page: _page + 1);
      if (!mounted || status != _status) return;
      setState(() {
        _trips.addAll(page.trips);
        _page = page.page;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _select(String? status) {
    if (status == _status) return;
    _status = status;
    _loadFirstPage();
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) return ErrorView(error: error, onRetry: _loadFirstPage);
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: _trips.isEmpty
          ? ListView(children: [
              const SizedBox(height: 96),
              EmptyView(
                icon: Icons.history,
                message: _status == null ? 'You have not offered any trips yet.' : 'No ${_filters[_status]!.toLowerCase()} trips.',
              ),
            ])
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _trips.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == _trips.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: BusyButton(busy: _loadingMore, onPressed: _loadMore, label: 'Show more'),
                  );
                }
                return _TripRow(trip: _trips[i]);
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trip history')),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            for (final filter in _filters.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(filter.value),
                  selected: _status == filter.key,
                  onSelected: (_) => _select(filter.key),
                ),
              ),
          ]),
        ),
        Expanded(child: _body()),
      ]),
    );
  }
}

class _TripRow extends StatelessWidget {
  final DriverTripSummary trip;
  const _TripRow({required this.trip});

  @override
  Widget build(BuildContext context) {
    final departure = trip.departureAt;
    final price = trip.basePriceCents;
    final seats = trip.seatsOffered;
    final reason = trip.cancelReason;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                '${trip.originName} → ${trip.destinationName}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 8),
            DriverStatusChip(trip.status),
          ]),
          if (departure != null) ...[const SizedBox(height: 6), Text(formatDateTime(departure))],
          if (seats != null || price != null) ...[
            const SizedBox(height: 2),
            Text(
              [
                if (seats != null) '$seats ${seats == 1 ? 'seat' : 'seats'}',
                if (price != null) formatLkr(price),
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (reason != null) ...[
            const SizedBox(height: 2),
            Text('Reason: $reason', style: Theme.of(context).textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }
}
