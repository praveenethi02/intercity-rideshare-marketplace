import 'package:flutter/material.dart';

import '../../../../core/app_services.dart';
import '../../../../core/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../models/search.dart';
import '../../models/trip.dart';
import '../../widgets/trip_widgets.dart';
import 'passenger_trip_detail_screen.dart';

enum _Sort { earliest, cheapest, closest }

/// List of trips that pass near the passenger's pickup and drop points.
class SearchResultsScreen extends StatefulWidget {
  final SearchQuery query;
  const SearchResultsScreen({super.key, required this.query});

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  late Future<SearchPage> _future;
  _Sort _sort = _Sort.earliest;
  bool _cargoOnly = false;

  @override
  void initState() {
    super.initState();
    _future = AppServices.of(context).trips.search(widget.query);
  }

  Future<void> _reload() async {
    final f = AppServices.of(context).trips.search(widget.query);
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  List<TripSearchResult> _sorted(List<TripSearchResult> items) {
    final list = items.where((r) => !_cargoOnly || r.allowsCargo).toList();
    switch (_sort) {
      case _Sort.earliest:
        list.sort((a, b) => a.pickupTime.compareTo(b.pickupTime));
      case _Sort.cheapest:
        list.sort((a, b) => a.segmentPriceCents.compareTo(b.segmentPriceCents));
      case _Sort.closest:
        list.sort((a, b) => a.walkingKm.compareTo(b.walkingKm));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.query;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${q.from.name} → ${q.to.name}', style: const TextStyle(fontSize: 18)),
          Text('${formatDate(q.date)} · ${q.seats} seat${q.seats > 1 ? 's' : ''}', style: const TextStyle(fontSize: 13)),
        ]),
      ),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            for (final s in _Sort.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(switch (s) {
                    _Sort.earliest => 'Earliest',
                    _Sort.cheapest => 'Cheapest',
                    _Sort.closest => 'Closest pickup',
                  }),
                  selected: _sort == s,
                  onSelected: (_) => setState(() => _sort = s),
                ),
              ),
            FilterChip(
              label: const Text('Takes cargo'),
              selected: _cargoOnly,
              onSelected: (v) => setState(() => _cargoOnly = v),
            ),
          ]),
        ),
        Expanded(
          child: FutureBuilder<SearchPage>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
              final results = _sorted(snap.data!.items);
              if (results.isEmpty) {
                return EmptyView(
                  icon: Icons.search_off,
                  message: 'No rides found within ${snap.data!.radiusKm.round()} km of your points on this day.\n'
                      'Try another date or a bigger pickup distance.',
                  action: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Change search')),
                );
              }
              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: results.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: Text('${results.length} ride${results.length == 1 ? '' : 's'} found',
                            style: Theme.of(context).textTheme.bodySmall),
                      );
                    }
                    final r = results[i - 1];
                    return _ResultCard(
                      result: r,
                      seats: q.seats,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PassengerTripDetailScreen(
                          tripId: r.tripId,
                          fromStop: r.pickup.order!,
                          toStop: r.drop.order!,
                          seats: q.seats,
                        ),
                      )),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final TripSearchResult result;
  final int seats;
  final VoidCallback onTap;
  const _ResultCard({required this.result, required this.seats, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = result;
    final isAuction = r.pricingMode == PricingMode.auction;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(formatTime(r.pickupTime), style: theme.textTheme.titleLarge),
                  Text('${r.pickup.name} → ${r.drop.name}', style: theme.textTheme.titleSmall),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatLkr(r.segmentPriceCents), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text(isAuction ? 'starting bid / seat' : 'per seat', style: theme.textTheme.bodySmall),
              ]),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              TagChip(PricingMode.label(r.pricingMode), icon: isAuction ? Icons.gavel : Icons.sell),
              TagChip('${r.seatsAvailable} seat${r.seatsAvailable == 1 ? '' : 's'} left', icon: Icons.event_seat),
              TagChip(formatKm(r.segmentDistanceKm), icon: Icons.route),
              if (r.allowsCargo) const TagChip('Cargo', icon: Icons.inventory_2),
            ]),
            const SizedBox(height: 8),
            Text(
              'Pickup ${formatKm(r.pickupDistanceKm)} from you · drop ${formatKm(r.dropDistanceKm)} from your destination',
              style: theme.textTheme.bodySmall,
            ),
            if (!isAuction && seats > 1)
              Text('Total for $seats seats: ${formatLkr(r.segmentPriceCents * seats)}', style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}
