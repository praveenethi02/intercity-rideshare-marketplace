import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/vehicle_api.dart';
import '../data/vehicle_models.dart';
import '../widgets/vehicle_widgets.dart';

/// SCRUM-48..52: add / edit a vehicle. [vehicleId] == null -> add mode.
class VehicleFormScreen extends ConsumerWidget {
  const VehicleFormScreen({super.key, this.vehicleId});
  final String? vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(vehicleTypesProvider);
    final vehicle = vehicleId == null ? null : ref.watch(vehicleProvider(vehicleId!));
    final title = vehicleId == null ? 'Add vehicle' : 'Edit vehicle';

    // wait for the type list (and the vehicle when editing)
    final error = types.error ?? vehicle?.error;
    final loading = types.isLoading || (vehicle?.isLoading ?? false);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: error != null
          ? ErrorView(
              message: apiErrorMessage(error),
              onRetry: () {
                ref.invalidate(vehicleTypesProvider);
                if (vehicleId != null) ref.invalidate(vehicleProvider(vehicleId!));
              },
            )
          : loading
              ? const LoadingView()
              : _VehicleForm(types: types.requireValue, existing: vehicle?.requireValue),
    );
  }
}

class _VehicleForm extends ConsumerStatefulWidget {
  const _VehicleForm({required this.types, this.existing});
  final List<VehicleTypeConfig> types;
  final Vehicle? existing;

  @override
  ConsumerState<_VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends ConsumerState<_VehicleForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _make, _model, _year, _color, _plate, _cargoKg, _cargoL;
  late String _type;
  late int _totalSeats;
  late int _passengerSeats;
  bool _saving = false;

  Vehicle? get _existing => widget.existing;
  bool get _isEdit => _existing != null;
  VehicleTypeConfig get _cfg => widget.types.firstWhere((t) => t.type == _type, orElse: () => widget.types.first);

  @override
  void initState() {
    super.initState();
    final v = _existing;
    _type = v?.vehicleType ?? widget.types.first.type;
    _totalSeats = v?.totalSeats ?? _cfg.maxSeats;
    _passengerSeats = v?.passengerSeats ?? _totalSeats - 1;
    _make = TextEditingController(text: v?.make ?? '');
    _model = TextEditingController(text: v?.model ?? '');
    _year = TextEditingController(text: v?.year.toString() ?? '');
    _color = TextEditingController(text: v?.color ?? '');
    _plate = TextEditingController(text: v?.plateNumber ?? '');
    _cargoKg = TextEditingController(text: (v?.cargoCapacityKg ?? 0).toString());
    _cargoL = TextEditingController(text: (v?.cargoVolumeL ?? 0).toString());
  }

  @override
  void dispose() {
    for (final c in [_make, _model, _year, _color, _plate, _cargoKg, _cargoL]) {
      c.dispose();
    }
    super.dispose();
  }

  // Keep seats inside the new type's limits when the type changes.
  void _onTypeChanged(String? type) {
    if (type == null) return;
    setState(() {
      _type = type;
      _totalSeats = _totalSeats.clamp(_cfg.minSeats, _cfg.maxSeats);
      _passengerSeats = _passengerSeats.clamp(1, _totalSeats - 1);
      if (!_cfg.allowsCargo) {
        _cargoKg.text = '0';
        _cargoL.text = '0';
      }
    });
  }

  Map<String, dynamic> _body() => {
        'vehicleType': _type,
        'make': _make.text.trim(),
        'model': _model.text.trim(),
        'year': int.parse(_year.text.trim()),
        'color': _color.text.trim(),
        'plateNumber': _plate.text.trim(),
        'totalSeats': _totalSeats,
        'passengerSeats': _passengerSeats,
        'cargoCapacityKg': _cfg.allowsCargo ? int.tryParse(_cargoKg.text) ?? 0 : 0,
        'cargoVolumeL': _cfg.allowsCargo ? int.tryParse(_cargoL.text) ?? 0 : 0,
      };

  /// For edit: send only changed fields.
  Map<String, dynamic> _changes(Map<String, dynamic> body) {
    final v = _existing!;
    final old = {
      'vehicleType': v.vehicleType,
      'make': v.make,
      'model': v.model,
      'year': v.year,
      'color': v.color,
      'plateNumber': v.plateNumber,
      'totalSeats': v.totalSeats,
      'passengerSeats': v.passengerSeats,
      'cargoCapacityKg': v.cargoCapacityKg,
      'cargoVolumeL': v.cargoVolumeL,
    };
    return {
      for (final e in body.entries)
        if (old[e.key] != e.value) e.key: e.value,
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final api = ref.read(vehicleApiProvider);
    final body = _body();

    if (_isEdit) {
      final changes = _changes(body);
      if (changes.isEmpty) {
        context.pop();
        return;
      }
      // Warn: these edits send an APPROVED vehicle back to admin review.
      if (_existing!.verificationStatus == 'APPROVED' && changes.keys.any(reverifyFields.contains)) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Re-verification needed'),
            content: const Text(
                'Changing plate, type, seats or cargo sends this vehicle back to admin review. '
                'You cannot use it for new trips until it is approved again.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
            ],
          ),
        );
        if (go != true) return;
      }
      await _run(() => api.update(_existing!.id, changes), (v) {
        refreshVehicle(ref, v.id);
        showSnack(context, 'Vehicle updated');
        context.pop();
      });
    } else {
      await _run(() => api.create(body), (v) {
        ref.invalidate(myVehiclesProvider);
        showSnack(context, 'Vehicle added. Now upload its documents.');
        context.pushReplacement('/vehicles/${v.id}/documents');
      });
    }
  }

  Future<void> _run(Future<Vehicle> Function() call, void Function(Vehicle) onDone) async {
    setState(() => _saving = true);
    try {
      final v = await call();
      if (mounted) onDone(v);
    } catch (e) {
      if (mounted) showSnack(context, apiErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _yearValidator(String? v) {
    final y = int.tryParse(v ?? '');
    final max = DateTime.now().year + 1;
    if (y == null || y < 1990 || y > max) return 'Enter a year between 1990 and $max';
    return null;
  }

  // Same rule as the API (accepts e.g. WP CAB-1234, CAB-1234, 65-1234).
  String? _plateValidator(String? v) {
    final p = (v ?? '').toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final ok = RegExp(r'^((WP|CP|SP|NP|EP|NW|NC|UP|SG) )?([A-Z]{2,3}|\d{2,3}) ?-? ?\d{4}$').hasMatch(p);
    return ok ? null : 'e.g. WP CAB-1234, CAB-1234 or 65-1234';
  }

  String? _cargoValidator(String? v, int max) {
    final n = int.tryParse(v ?? '');
    if (n == null || n < 0 || n > max) return 'Enter 0 - $max';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    final digits = [FilteringTextInputFormatter.digitsOnly];

    return AbsorbPointer(
      absorbing: _saving,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isEdit && _existing!.verificationStatus == 'PENDING')
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('This vehicle is waiting for admin review.'),
                ),
              ),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Vehicle type'),
              items: [
                for (final t in widget.types)
                  DropdownMenuItem(value: t.type, child: Text('${t.label} (${t.minSeats}-${t.maxSeats} seats)')),
              ],
              onChanged: _onTypeChanged,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Plate number', hintText: 'WP CAB-1234'),
              validator: _plateValidator,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _make,
                  decoration: const InputDecoration(labelText: 'Make', hintText: 'Toyota'),
                  validator: _required,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _model,
                  decoration: const InputDecoration(labelText: 'Model', hintText: 'Axio'),
                  validator: _required,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: const InputDecoration(labelText: 'Year'),
                  validator: _yearValidator,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _color,
                  decoration: const InputDecoration(labelText: 'Colour'),
                  validator: _required,
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Text('Capacity', style: Theme.of(context).textTheme.titleMedium),
            SeatStepper(
              label: 'Total seats',
              helper: 'Including the driver (${cfg.minSeats}-${cfg.maxSeats} for ${cfg.label})',
              value: _totalSeats,
              min: cfg.minSeats,
              max: cfg.maxSeats,
              onChanged: (n) => setState(() {
                _totalSeats = n;
                _passengerSeats = _passengerSeats.clamp(1, n - 1);
              }),
            ),
            SeatStepper(
              label: 'Seats you can sell',
              helper: 'The most seats a trip can offer',
              value: _passengerSeats,
              min: 1,
              max: _totalSeats - 1,
              onChanged: (n) => setState(() => _passengerSeats = n),
            ),
            if (cfg.allowsCargo) ...[
              const SizedBox(height: 12),
              Text('Cargo space (0 = no cargo)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _cargoKg,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: InputDecoration(labelText: 'Weight (kg)', helperText: 'max ${cfg.maxCargoKg}'),
                    validator: (v) => _cargoValidator(v, cfg.maxCargoKg),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _cargoL,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: InputDecoration(labelText: 'Volume (L)', helperText: 'max ${cfg.maxCargoVolumeL}'),
                    validator: (v) => _cargoValidator(v, cfg.maxCargoVolumeL),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_isEdit ? 'Save changes' : 'Add vehicle'),
            ),
          ],
        ),
      ),
    );
  }
}
