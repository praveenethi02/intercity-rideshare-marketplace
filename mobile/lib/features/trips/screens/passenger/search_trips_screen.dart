import 'package:flutter/material.dart';

import '../../../../core/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../data/towns.dart';
import '../../models/search.dart';
import '../../models/trip.dart';
import '../../models/trip_draft.dart';
import '../shared/stop_picker_screen.dart';
import 'search_results_screen.dart';

/// Passenger: where from, where to, when, how many seats.
class SearchTripsScreen extends StatefulWidget {
  const SearchTripsScreen({super.key});

  @override
  State<SearchTripsScreen> createState() => _SearchTripsScreenState();
}

class _SearchTripsScreenState extends State<SearchTripsScreen> {
  TripStop? _from;
  TripStop? _to;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  int _seats = 1;
  String? _mode; // null = any
  double _radiusKm = 5;

  Future<void> _pick(bool isFrom) async {
    final other = isFrom ? _to : _from;
    final stop = await StopPickerScreen.open(
      context,
      title: isFrom ? 'Where from?' : 'Where to?',
      exclude: other == null ? const [] : [other.name],
    );
    if (stop == null) return;
    setState(() {
      if (isFrom) {
        _from = stop;
      } else {
        _to = stop;
      }
    });
  }

  void _swap() => setState(() {
        final f = _from;
        _from = _to;
        _to = f;
      });

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: TripRules.maxDaysAhead)),
    );
    if (d != null) setState(() => _date = d);
  }

  void _search() {
    if (_from == null || _to == null) {
      showSnack(context, 'Choose where you start and where you are going');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchResultsScreen(
        query: SearchQuery(from: _from!, to: _to!, date: _date, seats: _seats, pricingMode: _mode, radiusKm: _radiusKm),
      ),
    ));
  }

  Widget _placeTile(String label, TripStop? stop, IconData icon, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(stop?.name ?? label, style: stop == null ? TextStyle(color: Theme.of(context).colorScheme.outline) : null),
        subtitle: stop == null ? null : Text(label),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

    return Scaffold(
      appBar: AppBar(title: const Text('Find a ride')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Column(children: [
            _placeTile('Where from?', _from, Icons.trip_origin, () => _pick(true)),
            Row(children: [
              const Expanded(child: Divider(indent: 56)),
              IconButton(tooltip: 'Swap', onPressed: _swap, icon: const Icon(Icons.swap_vert)),
            ]),
            _placeTile('Where to?', _to, Icons.flag, () => _pick(false)),
          ]),
        ),
        const SectionTitle('When'),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('Today'), selected: sameDay(_date, today), onSelected: (_) => setState(() => _date = today)),
          ChoiceChip(
            label: const Text('Tomorrow'),
            selected: sameDay(_date, tomorrow),
            onSelected: (_) => setState(() => _date = tomorrow),
          ),
          ActionChip(avatar: const Icon(Icons.calendar_today, size: 18), label: Text(formatDate(_date)), onPressed: _pickDate),
        ]),
        const SectionTitle('Seats'),
        Row(children: [
          const Expanded(child: Text('Passengers')),
          NumberStepper(value: _seats, max: 6, onChanged: (v) => setState(() => _seats = v)),
        ]),
        const SectionTitle('Price type'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'ANY', label: Text('Any')),
            ButtonSegment(value: PricingMode.fixed, label: Text('Fixed')),
            ButtonSegment(value: PricingMode.auction, label: Text('Auction')),
          ],
          selected: {_mode ?? 'ANY'},
          onSelectionChanged: (s) => setState(() => _mode = s.first == 'ANY' ? null : s.first),
        ),
        SectionTitle('Pickup within ${_radiusKm.round()} km of me'),
        Slider(
          value: _radiusKm,
          min: 1,
          max: 30,
          divisions: 29,
          label: '${_radiusKm.round()} km',
          onChanged: (v) => setState(() => _radiusKm = v),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _search, icon: const Icon(Icons.search), label: const Text('Search rides')),
        const SizedBox(height: 24),
        const SectionTitle('Popular routes'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final pair in const [
            ['Colombo Fort', 'Kandy'],
            ['Colombo Fort', 'Galle'],
            ['Kandy', 'Kurunegala'],
            ['Colombo Fort', 'Jaffna'],
          ])
            ActionChip(
              label: Text('${pair[0]} → ${pair[1]}'),
              onPressed: () => setState(() {
                _from = kTowns.firstWhere((t) => t.name == pair[0]);
                _to = kTowns.firstWhere((t) => t.name == pair[1]);
              }),
            ),
        ]),
      ]),
    );
  }
}
