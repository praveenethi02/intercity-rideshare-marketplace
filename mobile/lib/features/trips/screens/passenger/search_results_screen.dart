import 'package:flutter/material.dart';

import '../../../../core/app_services.dart';
import '../../../../core/formatters.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../models/search.dart';
import '../../widgets/search_result_card.dart';
import 'passenger_trip_detail_screen.dart';

/// Trips that pass near the passenger's pickup and drop points (SCRUM-67, SCRUM-69).
/// Sorting and filters are done by the server, so they cover every page; the next page
/// loads when the user reaches the end of the list.
class SearchResultsScreen extends StatefulWidget {
  final SearchQuery query;
  const SearchResultsScreen({super.key, required this.query});

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  late SearchQuery _query = widget.query;

  final List<TripSearchResult> _items = [];
  int _total = 0;
  int _page = 0; // last page loaded
  double _radiusKm = 5;

  bool _loading = true; // first page
  bool _loadingMore = false;
  Object? _error; // first page failed
  Object? _pageError; // a later page failed

  /// Grows with every new search. A response for an older search is ignored.
  int _generation = 0;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _load(first: true);
  }

  /// Loads page 1 for the current sort and filters and replaces the list.
  Future<void> _load({bool first = false}) async {
    final generation = ++_generation;
    void reset() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _pageError = null;
    }

    // setState cannot be called from initState.
    if (first) {
      reset();
    } else {
      setState(reset);
    }
    try {
      final page = await AppServices.of(context).trips.search(_query, page: 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _total = page.total;
        _page = 1;
        _radiusKm = page.radiusKm;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _pageError != null) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await AppServices.of(context).trips.search(_query, page: _page + 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        // An empty page means the list changed on the server: stop asking for more.
        _total = page.items.isEmpty ? _items.length : page.total;
        _page = page.page;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _pageError = e;
        _loadingMore = false;
      });
    }
  }

  void _retryPage() {
    setState(() => _pageError = null);
    _loadMore();
  }

  void _setSort(String sort) {
    if (sort == _query.sort) return;
    _query = _query.copyWith(sort: sort);
    _load();
  }

  void _setFilters(SearchFilters filters) {
    if (filters == _query.filters) return;
    _query = _query.copyWith(filters: filters);
    _load();
  }

  Future<void> _openFilters() async {
    final picked = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SearchFiltersSheet(initial: _query.filters),
    );
    if (picked != null && mounted) _setFilters(picked);
  }

  Future<void> _openTrip(TripSearchResult r) async {
    var seatsChanged = false;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PassengerTripDetailScreen(
        tripId: r.tripId,
        fromStop: r.pickup.order!,
        toStop: r.drop.order!,
        seats: _query.seats,
        onSeatsChanged: () => seatsChanged = true,
      ),
    ));
    if (mounted && seatsChanged) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query;
    final activeFilters = q.filters.activeCount;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${q.from.name} → ${q.to.name}', overflow: TextOverflow.ellipsis),
          Text(
            '${formatDate(q.date)} · ${q.seats} seat${q.seats > 1 ? 's' : ''}',
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ]),
      ),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ActionChip(
                avatar: const Icon(Icons.tune, size: 18),
                label: Text(activeFilters == 0 ? 'Filters' : 'Filters ($activeFilters)'),
                tooltip: 'Filter rides',
                onPressed: _openFilters,
              ),
            ),
            for (final s in SearchSort.values)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: ChoiceChip(
                  label: Text(SearchSort.label(s)),
                  selected: q.sort == s,
                  onSelected: (_) => _setSort(s),
                ),
              ),
          ]),
        ),
        Expanded(child: _body(theme)),
      ]),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) return const SkeletonList();
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    if (_items.isEmpty) {
      final filtered = !_query.filters.isEmpty;
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          EmptyView(
            icon: Icons.search_off,
            message: filtered
                ? 'No rides match your filters.'
                : 'No rides found within ${_radiusKm.round()} km of your points on this day.\n'
                    'Try another date or a bigger pickup distance.',
            action: filtered
                ? FilledButton.icon(
                    onPressed: () => _setFilters(SearchFilters.none),
                    icon: const Icon(Icons.filter_alt_off),
                    label: const Text('Clear filters'),
                  )
                : OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Change search')),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
        // A header, the results and a footer (spinner, retry row or nothing).
        itemCount: _items.length + 2,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, AppSpacing.sm),
              child: Text(
                '$_total ride${_total == 1 ? '' : 's'} found',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            );
          }
          if (i == _items.length + 1) return _footer(theme);
          final r = _items[i - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: TripResultCard(result: r, seats: _query.seats, onTap: () => _openTrip(r)),
          );
        },
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    if (_pageError != null) {
      return AppCard(
        child: Row(children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: AppSpacing.md),
          const Expanded(child: Text('Could not load more rides.')),
          TextButton(onPressed: _retryPage, child: const Text('Retry')),
        ]),
      );
    }
    if (!_hasMore) return const SizedBox.shrink();
    // Reaching the end of the list loads the next page.
    if (!_loadingMore) WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Bottom sheet with the search filters (SCRUM-69). Pops the chosen [SearchFilters], or
/// [SearchFilters.none] for Clear.
class SearchFiltersSheet extends StatefulWidget {
  final SearchFilters initial;
  const SearchFiltersSheet({super.key, this.initial = SearchFilters.none});

  @override
  State<SearchFiltersSheet> createState() => _SearchFiltersSheetState();
}

class _SearchFiltersSheetState extends State<SearchFiltersSheet> {
  late final _maxPrice = TextEditingController(
    text: widget.initial.maxPriceCents == null ? '' : '${(widget.initial.maxPriceCents! / 100).round()}',
  );
  late final _minCargo = TextEditingController(
    text: widget.initial.minCargoKg == null ? '' : _plain(widget.initial.minCargoKg!),
  );
  late String? _after = widget.initial.departAfter;
  late String? _before = widget.initial.departBefore;
  late bool _cargo = widget.initial.allowsCargo;
  String? _priceError;
  String? _cargoError;
  String? _timeError;

  static String _plain(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  @override
  void dispose() {
    _maxPrice.dispose();
    _minCargo.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool after) async {
    final current = after ? _after : _before;
    final parts = (current ?? (after ? '06:00' : '18:00')).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      helpText: after ? 'Leaving after' : 'Leaving before',
    );
    if (picked == null || !mounted) return;
    setState(() {
      final value = clockTime(picked.hour, picked.minute);
      if (after) {
        _after = value;
      } else {
        _before = value;
      }
      _timeError = null;
    });
  }

  void _apply() {
    final priceText = _maxPrice.text.trim();
    final cargoText = _minCargo.text.trim();
    final maxPrice = priceText.isEmpty ? null : parseLkrToCents(priceText);
    final minCargo = cargoText.isEmpty ? null : double.tryParse(cargoText);
    setState(() {
      _priceError = priceText.isNotEmpty && maxPrice == null ? 'Enter an amount in LKR' : null;
      _cargoError = cargoText.isNotEmpty && (minCargo == null || minCargo <= 0 || minCargo > 2000)
          ? 'Enter a weight between 1 and 2000 kg'
          : null;
      _timeError = _after != null && _before != null && _after!.compareTo(_before!) >= 0
          ? 'The first time must be before the second'
          : null;
    });
    if (_priceError != null || _cargoError != null || _timeError != null) return;
    Navigator.pop(
      context,
      SearchFilters(
        maxPriceCents: maxPrice,
        departAfter: _after,
        departBefore: _before,
        allowsCargo: _cargo,
        minCargoKg: minCargo,
      ),
    );
  }

  Widget _timeButton(String label, String? value, bool after) => Expanded(
        child: OutlinedButton(
          onPressed: () => _pickTime(after),
          child: Text(value == null ? label : '$label ${formatClockTime(value)}', overflow: TextOverflow.ellipsis),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Filters', style: theme.textTheme.titleLarge),
          const SectionTitle('Price per seat'),
          TextField(
            key: const Key('maxPrice'),
            controller: _maxPrice,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Highest price (LKR)', prefixText: 'LKR ', errorText: _priceError),
          ),
          SectionTitle(
            'Departure time',
            trailing: _after == null && _before == null
                ? null
                : IconButton(
                    tooltip: 'Clear departure time',
                    onPressed: () => setState(() {
                      _after = null;
                      _before = null;
                      _timeError = null;
                    }),
                    icon: const Icon(Icons.close),
                  ),
          ),
          Row(children: [
            _timeButton('After', _after, true),
            const SizedBox(width: AppSpacing.sm),
            _timeButton('Before', _before, false),
          ]),
          if (_timeError != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(_timeError!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ),
          const SectionTitle('Cargo'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Takes cargo'),
            value: _cargo,
            onChanged: (v) => setState(() => _cargo = v),
          ),
          TextField(
            key: const Key('minCargo'),
            controller: _minCargo,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'At least (kg)', suffixText: 'kg', errorText: _cargoError),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, SearchFilters.none),
                child: const Text('Clear'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: FilledButton(onPressed: _apply, child: const Text('Apply'))),
          ]),
        ]),
      ),
    );
  }
}
