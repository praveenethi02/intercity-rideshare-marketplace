import 'package:flutter/material.dart';

import '../../../../core/api_client.dart';
import '../../../../core/app_services.dart';
import '../../../../core/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../models/trip.dart';
import '../../models/trip_draft.dart';
import '../../widgets/stop_list_editor.dart';

/// Edit a trip. Which fields are enabled depends on [Trip.editMode]
/// (same rules as the backend). Pops with the updated [Trip].
class EditTripScreen extends StatefulWidget {
  final Trip trip;
  const EditTripScreen({super.key, required this.trip});

  @override
  State<EditTripScreen> createState() => _EditTripScreenState();
}

class _EditTripScreenState extends State<EditTripScreen> {
  final _formKey = GlobalKey<FormState>();
  late List<TripStop> _stops;
  late DateTime _departure;
  DateTime? _arrival;
  late int _seats;
  late bool _cargo;
  late final TextEditingController _price;
  late final TextEditingController _cargoKg;
  late final TextEditingController _notes;
  bool _saving = false;

  Trip get t => widget.trip;
  TripEditMode get mode => t.editMode;
  bool get _full => mode == TripEditMode.full;
  bool get _pricing => mode == TripEditMode.full || mode == TripEditMode.limited;

  @override
  void initState() {
    super.initState();
    _stops = t.stops.map((s) => TripStop(name: s.name, lat: s.lat, lng: s.lng)).toList();
    _departure = t.departureTime;
    _arrival = t.estArrivalTime;
    _seats = t.seatsOffered;
    _cargo = t.allowsCargo;
    _price = TextEditingController(text: (t.basePriceCents / 100).toStringAsFixed(0));
    _cargoKg = TextEditingController(text: t.cargoCapacityKg?.toStringAsFixed(0) ?? '50');
    _notes = TextEditingController(text: t.notes ?? '');
  }

  @override
  void dispose() {
    _price.dispose();
    _cargoKg.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool _stopsChanged() {
    if (_stops.length != t.stops.length) return true;
    for (var i = 0; i < _stops.length; i++) {
      if (!_stops[i].samePlaceAs(t.stops[i])) return true;
    }
    return false;
  }

  /// Only the fields that are allowed AND changed.
  Map<String, dynamic> _changes() {
    final c = <String, dynamic>{};
    if (_full) {
      if (_stopsChanged()) c['stops'] = _stops.map((s) => s.toJson()).toList();
      if (_departure != t.departureTime) c['departureAt'] = _departure.toUtc().toIso8601String();
      if (_cargo != t.allowsCargo) c['allowsCargo'] = _cargo;
      final kg = double.tryParse(_cargoKg.text);
      if (_cargo && kg != null && kg != t.cargoCapacityKg) c['cargoCapacityKg'] = kg;
    }
    if (_pricing) {
      if (_seats != t.seatsOffered) c['seatsOffered'] = _seats;
      final cents = parseLkrToCents(_price.text);
      if (cents != null && cents != t.basePriceCents) c['basePriceCents'] = cents;
    }
    if (_arrival != null && _arrival != t.estArrivalTime) c['estimatedArrivalAt'] = _arrival!.toUtc().toIso8601String();
    if (_notes.text.trim() != (t.notes ?? '')) c['notes'] = _notes.text.trim();
    return c;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final error = (_full ? TripRules.checkStops(_stops) : null) ??
        (_full && _departure != t.departureTime ? TripRules.checkDeparture(_departure, DateTime.now()) : null) ??
        TripRules.checkArrival(_arrival, _departure);
    if (error != null) {
      showSnack(context, error);
      return;
    }
    final changes = _changes();
    if (changes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await AppServices.of(context).trips.updateTrip(t.id, changes);
      if (!mounted) return;
      showSnack(context, 'Trip updated');
      Navigator.pop(context, updated);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<DateTime?> _pick(DateTime initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: TripRules.maxDaysAhead)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String get _modeHint => switch (mode) {
        TripEditMode.full => 'Draft trip: you can change everything.',
        TripEditMode.limited => 'Scheduled trip: the route and departure time are locked.',
        TripEditMode.notesOnly => 'Seats are reserved: only arrival time and notes can change.',
        TripEditMode.none => 'This trip can no longer be edited.',
      };

  @override
  Widget build(BuildContext context) {
    final maxSeats = AppServices.of(context).maxSeatsToOffer;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit trip')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: ListTile(leading: const Icon(Icons.info_outline), title: Text(_modeHint)),
          ),
          if (_full) ...[
            const SectionTitle('Route'),
            StopListEditor(stops: _stops, onChanged: (s) => setState(() => _stops = s)),
          ],
          const SectionTitle('Schedule'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: _full,
            leading: const Icon(Icons.schedule),
            title: const Text('Departure'),
            subtitle: Text(formatDateTime(_departure)),
            trailing: _full ? const Icon(Icons.edit_calendar) : const Icon(Icons.lock_outline),
            onTap: _full
                ? () async {
                    final d = await _pick(_departure);
                    if (d != null) setState(() => _departure = d);
                  }
                : null,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: mode != TripEditMode.none,
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Estimated arrival'),
            subtitle: Text(_arrival == null ? 'Not set' : formatDateTime(_arrival!)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: mode == TripEditMode.none
                ? null
                : () async {
                    final d = await _pick(_arrival ?? _departure.add(const Duration(hours: 3)));
                    if (d != null) setState(() => _arrival = d);
                  },
          ),
          const SectionTitle('Seats & price'),
          Row(children: [
            const Expanded(child: Text('Seats to offer')),
            if (_pricing)
              NumberStepper(value: _seats, max: maxSeats, onChanged: (v) => setState(() => _seats = v))
            else
              Text('$_seats', style: Theme.of(context).textTheme.titleMedium),
          ]),
          TextFormField(
            controller: _price,
            enabled: _pricing,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: t.pricingMode == PricingMode.auction ? 'Starting bid, full route' : 'Seat price, full route',
              prefixText: 'LKR ',
            ),
            validator: (v) => parseLkrToCents(v ?? '') == null ? 'Enter an amount' : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Carry cargo'),
            value: _cargo,
            onChanged: _full ? (v) => setState(() => _cargo = v) : null,
          ),
          if (_cargo)
            TextFormField(
              controller: _cargoKg,
              enabled: _full,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Cargo space', suffixText: 'kg'),
              validator: (v) {
                final kg = double.tryParse(v ?? '');
                return (kg == null || kg <= 0 || kg > TripRules.maxCargoKg) ? 'Enter 1 – 2000 kg' : null;
              },
            ),
          TextFormField(
            controller: _notes,
            enabled: mode != TripEditMode.none,
            maxLength: TripRules.maxNotes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes for passengers'),
          ),
          const SizedBox(height: 16),
          BusyButton(busy: _saving, onPressed: mode == TripEditMode.none ? null : _save, label: 'Save changes'),
        ]),
      ),
    );
  }
}
