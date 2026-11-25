import 'package:flutter/material.dart';

import '../../../../core/formatters.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../data/towns.dart';
import '../../models/search.dart';
import '../../models/trip.dart';
import '../../models/trip_draft.dart';
import '../shared/stop_picker_screen.dart';
import 'search_results_screen.dart';

/// Passenger: where from, where to, when, how many seats (SCRUM-68).
class SearchTripsScreen extends StatefulWidget {
  /// Start values, e.g. from a deep link or a test.
  final TripStop? initialFrom;
  final TripStop? initialTo;

  /// The search history of this app session. Tests pass their own.
  final RecentSearches? recentSearches;

  const SearchTripsScreen({super.key, this.initialFrom, this.initialTo, this.recentSearches});

  /// Shown when the start and the end are the same place.
  static const samePlaceMessage = 'Start and destination are the same place. Choose two different places.';

  @override
  State<SearchTripsScreen> createState() => _SearchTripsScreenState();
}

class _SearchTripsScreenState extends State<SearchTripsScreen> {
  late TripStop? _from = widget.initialFrom;
  late TripStop? _to = widget.initialTo;
  DateTime _date = _today().add(const Duration(days: 1));
  int _seats = 1;
  String? _mode; // null = any
  double _radiusKm = 5;

  RecentSearches get _recent => widget.recentSearches ?? RecentSearches.instance;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _samePlace => _from != null && _to != null && isSamePlace(_from!, _to!);

  Future<void> _pick(bool isFrom) async {
    final other = isFrom ? _to : _from;
    final stop = await StopPickerScreen.open(
      context,
      title: isFrom ? 'Where from?' : 'Where to?',
      exclude: other == null ? const [] : [other.name],
    );
    if (stop == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = stop;
      } else {
        _to = stop;
      }
    });
    if (_samePlace) showSnack(context, SearchTripsScreen.samePlaceMessage);
  }

  void _swap() => setState(() {
        final f = _from;
        _from = _to;
        _to = f;
      });

  Future<void> _pickDate() async {
    final today = _today();
    final d = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: today.add(const Duration(days: TripRules.maxDaysAhead)),
    );
    if (d != null) setState(() => _date = d);
  }

  /// Fills the form from a recent search. Its date is kept only if it is not in the past.
  void _useRecent(SearchQuery q) => setState(() {
        _from = q.from;
        _to = q.to;
        _seats = q.seats;
        _mode = q.pricingMode;
        _radiusKm = q.radiusKm ?? 5;
        if (!q.date.isBefore(_today())) _date = q.date;
      });

  void _search() {
    if (_from == null || _to == null) {
      showSnack(context, 'Choose where you start and where you are going');
      return;
    }
    if (_samePlace) {
      showSnack(context, SearchTripsScreen.samePlaceMessage);
      return;
    }
    final query = SearchQuery(
      from: _from!,
      to: _to!,
      date: _date,
      seats: _seats,
      pricingMode: _mode,
      radiusKm: _radiusKm,
    );
    setState(() => _recent.add(query));
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchResultsScreen(query: query)));
  }

  Widget _placeTile(String label, TripStop? stop, IconData icon, VoidCallback onTap) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: colors.primary),
      title: Text(stop?.name ?? label, style: stop == null ? TextStyle(color: colors.onSurfaceVariant) : null),
      subtitle: stop == null ? null : Text(label),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _today();
    final tomorrow = today.add(const Duration(days: 1));
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    final recent = _recent.items;

    return Scaffold(
      appBar: AppBar(title: const Text('Find a ride')),
      body: ListView(padding: AppSpacing.screen, children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            _placeTile('Where from?', _from, Icons.trip_origin, () => _pick(true)),
            Row(children: [
              const Expanded(child: Divider(indent: 56)),
              IconButton(tooltip: 'Swap start and destination', onPressed: _swap, icon: const Icon(Icons.swap_vert)),
            ]),
            _placeTile('Where to?', _to, Icons.flag, () => _pick(false)),
          ]),
        ),
        if (_samePlace)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              SearchTripsScreen.samePlaceMessage,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        const SectionTitle('When'),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
          ChoiceChip(
            label: const Text('Today'),
            selected: sameDay(_date, today),
            onSelected: (_) => setState(() => _date = today),
          ),
          ChoiceChip(
            label: const Text('Tomorrow'),
            selected: sameDay(_date, tomorrow),
            onSelected: (_) => setState(() => _date = tomorrow),
          ),
          ActionChip(
            avatar: const Icon(Icons.calendar_today, size: 18),
            label: Text(formatDate(_date)),
            tooltip: 'Choose a date',
            onPressed: _pickDate,
          ),
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
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(onPressed: _search, icon: const Icon(Icons.search), label: const Text('Search rides')),
        if (recent.isNotEmpty) ...[
          SectionTitle(
            'Recent searches',
            trailing: TextButton(
              onPressed: () => setState(_recent.clear),
              child: const Text('Clear'),
            ),
          ),
          for (final q in recent)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                onTap: () => _useRecent(q),
                child: Row(children: [
                  Icon(Icons.history, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${q.from.name} → ${q.to.name}', style: theme.textTheme.titleSmall),
                      Text(
                        '${formatDate(q.date)} · ${q.seats} seat${q.seats > 1 ? 's' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
        ],
        const SectionTitle('Popular routes'),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
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
