import 'package:flutter/material.dart';

import '../../../../core/api_client.dart';
import '../../../../core/app_services.dart';
import '../../../../core/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../data/towns.dart';
import '../../models/saved_route.dart';
import '../../models/trip.dart';
import '../../models/trip_draft.dart';
import '../../widgets/stop_list_editor.dart';
import '../../widgets/trip_widgets.dart';
import 'driver_trip_detail_screen.dart';
import 'saved_routes_screen.dart';

/// 4-step wizard: Route → Schedule → Seats & price → Review.
class CreateTripScreen extends StatefulWidget {
  /// Optional: start from a saved route.
  final SavedRoute? fromSavedRoute;
  const CreateTripScreen({super.key, this.fromSavedRoute});

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  int _step = 0;
  bool _saving = false;

  // step 1: route
  late List<TripStop> _stops;

  // step 2: schedule
  late DateTime _departure;
  DateTime? _arrival;

  // step 3: seats & price
  String _mode = PricingMode.fixed;
  int _seats = 3;
  final _priceCtrl = TextEditingController();
  bool _cargo = false;
  final _cargoCtrl = TextEditingController(text: '50');
  final _notesCtrl = TextEditingController();
  final _priceFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _stops = widget.fromSavedRoute?.stops.toList() ?? [kTowns[0], kTowns[8]]; // Colombo Fort -> Kandy
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _departure = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 6, 0);
    final max = AppServices.of(context).maxSeatsToOffer;
    if (_seats > max) _seats = max;
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _cargoCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ---------- validation per step ----------
  String? _stepError(int step) {
    switch (step) {
      case 0:
        return TripRules.checkStops(_stops);
      case 1:
        return TripRules.checkDeparture(_departure, DateTime.now()) ?? TripRules.checkArrival(_arrival, _departure);
      case 2:
        return _priceFormKey.currentState?.validate() == false ? 'Fix the highlighted fields' : null;
      default:
        return null;
    }
  }

  void _next() {
    final error = _stepError(_step);
    if (error != null) {
      showSnack(context, error);
      return;
    }
    if (_step < 3) setState(() => _step++);
  }

  TripDraft _buildDraft() => TripDraft(
        vehicleId: AppServices.of(context).driverVehicleId!,
        pricingMode: _mode,
        departureTime: _departure,
        estArrivalTime: _arrival,
        seatsOffered: _seats,
        basePriceCents: parseLkrToCents(_priceCtrl.text) ?? 0,
        allowsCargo: _cargo,
        cargoCapacityKg: _cargo ? double.tryParse(_cargoCtrl.text) : null,
        notes: _notesCtrl.text,
        stops: _stops,
      );

  Future<void> _save({required bool publish}) async {
    for (var s = 0; s < 3; s++) {
      final error = _stepError(s);
      if (error != null) {
        setState(() => _step = s);
        showSnack(context, error);
        return;
      }
    }
    setState(() => _saving = true);
    final repo = AppServices.of(context).trips;
    try {
      var trip = await repo.createTrip(_buildDraft());
      if (publish) trip = await repo.publish(trip.id);
      if (!mounted) return;
      showSnack(context, publish ? 'Trip published' : 'Saved as draft');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => DriverTripDetailScreen(tripId: trip.id)),
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _useSavedRoute() async {
    final route = await Navigator.of(context).push<SavedRoute>(
      MaterialPageRoute(builder: (_) => const SavedRoutesScreen(pickMode: true)),
    );
    if (route != null) setState(() => _stops = route.stops.toList());
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
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

  // ---------- step content ----------
  Widget _routeStep() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StopListEditor(stops: _stops, onChanged: (s) => setState(() => _stops = s)),
        OutlinedButton.icon(
          onPressed: _useSavedRoute,
          icon: const Icon(Icons.bookmarks_outlined),
          label: const Text('Use a saved route'),
        ),
      ]);

  Widget _scheduleStep() => Column(children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: const Text('Departure'),
          subtitle: Text(formatDateTime(_departure)),
          trailing: const Icon(Icons.edit_calendar),
          onTap: () async {
            final picked = await _pickDateTime(_departure);
            if (picked != null) setState(() => _departure = picked);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Estimated arrival (optional)'),
          subtitle: Text(_arrival == null
              ? 'Not set'
              : '${formatDateTime(_arrival!)} (${formatDuration(_arrival!.difference(_departure))})'),
          trailing: _arrival == null
              ? const Icon(Icons.edit_calendar)
              : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _arrival = null)),
          onTap: () async {
            final picked = await _pickDateTime(_arrival ?? _departure.add(const Duration(hours: 3)));
            if (picked != null) setState(() => _arrival = picked);
          },
        ),
      ]);

  Widget _priceStep() {
    final maxSeats = AppServices.of(context).maxSeatsToOffer;
    return Form(
      key: _priceFormKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: PricingMode.fixed, label: Text('Fixed price'), icon: Icon(Icons.sell)),
            ButtonSegment(value: PricingMode.auction, label: Text('Seat auction'), icon: Icon(Icons.gavel)),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 4),
        Text(
          _mode == PricingMode.fixed
              ? 'Passengers book at the price you set.'
              : 'Passengers bid for seats; the highest bids win.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Text('Seats to offer')),
          NumberStepper(value: _seats, max: maxSeats, onChanged: (v) => setState(() => _seats = v)),
        ]),
        const SizedBox(height: 12),
        TextFormField(
          controller: _priceCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: _mode == PricingMode.fixed ? 'Seat price, full route (LKR)' : 'Starting bid, full route (LKR)',
            helperText: 'Shorter trips inside your route are priced by distance',
            prefixText: 'LKR ',
          ),
          validator: (v) {
            final cents = parseLkrToCents(v ?? '');
            if (cents == null) return 'Enter an amount';
            if (cents > 10000000) return 'Maximum is LKR 100,000';
            return null;
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Carry cargo on this trip'),
          subtitle: const Text('Customers can send parcels along your route'),
          value: _cargo,
          onChanged: (v) => setState(() => _cargo = v),
        ),
        if (_cargo)
          TextFormField(
            controller: _cargoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Cargo space (kg)', suffixText: 'kg'),
            validator: (v) {
              final kg = double.tryParse(v ?? '');
              if (kg == null || kg <= 0) return 'Enter the weight you can carry';
              if (kg > TripRules.maxCargoKg) return 'Maximum is ${TripRules.maxCargoKg.round()} kg';
              return null;
            },
          ),
        TextFormField(
          controller: _notesCtrl,
          maxLength: TripRules.maxNotes,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Notes for passengers (optional)', hintText: 'e.g. AC car, no smoking'),
        ),
      ]),
    );
  }

  Widget _reviewStep() {
    final price = parseLkrToCents(_priceCtrl.text) ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RouteTimeline(stops: _stops),
      const Divider(),
      InfoRow(icon: Icons.schedule, label: 'Departure', value: formatDateTime(_departure)),
      if (_arrival != null) InfoRow(icon: Icons.flag_outlined, label: 'Arrival', value: formatDateTime(_arrival!)),
      InfoRow(icon: Icons.sell, label: 'Pricing', value: PricingMode.label(_mode)),
      InfoRow(icon: Icons.event_seat, label: 'Seats', value: '$_seats'),
      InfoRow(
        icon: Icons.payments_outlined,
        label: _mode == PricingMode.fixed ? 'Seat price (full route)' : 'Starting bid (full route)',
        value: formatLkr(price),
      ),
      if (_cargo) InfoRow(icon: Icons.inventory_2_outlined, label: 'Cargo space', value: '${_cargoCtrl.text} kg'),
      if (_notesCtrl.text.trim().isNotEmpty) InfoRow(icon: Icons.notes, label: 'Notes', value: _notesCtrl.text.trim()),
      const SizedBox(height: 8),
      Text(
        'Distance and per-stop prices are calculated by the server after saving.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New trip')),
      body: Stepper(
        currentStep: _step,
        onStepTapped: (s) {
          // can always go back; going forward checks the current step
          if (s <= _step) {
            setState(() => _step = s);
          } else {
            _next();
          }
        },
        onStepContinue: _next,
        onStepCancel: _step == 0 ? null : () => setState(() => _step--),
        controlsBuilder: (context, details) {
          if (details.stepIndex == 3) {
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Wrap(spacing: 12, runSpacing: 8, children: [
                BusyButton(busy: _saving, onPressed: () => _save(publish: true), label: 'Save & publish'),
                OutlinedButton(onPressed: _saving ? null : () => _save(publish: false), child: const Text('Save as draft')),
                TextButton(onPressed: _saving ? null : details.onStepCancel, child: const Text('Back')),
              ]),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(children: [
              FilledButton(onPressed: details.onStepContinue, child: const Text('Next')),
              const SizedBox(width: 12),
              if (details.stepIndex > 0) TextButton(onPressed: details.onStepCancel, child: const Text('Back')),
            ]),
          );
        },
        steps: [
          Step(
            title: const Text('Route'),
            subtitle: Text(_stops.length >= 2 ? '${_stops.first.name} → ${_stops.last.name}' : ''),
            isActive: _step >= 0,
            state: _step > 0 ? StepState.complete : StepState.indexed,
            content: _routeStep(),
          ),
          Step(
            title: const Text('Schedule'),
            subtitle: _step > 1 ? Text(formatDateTime(_departure)) : null,
            isActive: _step >= 1,
            state: _step > 1 ? StepState.complete : StepState.indexed,
            content: _scheduleStep(),
          ),
          Step(
            title: const Text('Seats & price'),
            isActive: _step >= 2,
            state: _step > 2 ? StepState.complete : StepState.indexed,
            content: _priceStep(),
          ),
          Step(
            title: const Text('Review'),
            isActive: _step >= 3,
            content: _reviewStep(),
          ),
        ],
      ),
    );
  }
}
