import 'package:flutter/material.dart';

import '../../../core/widgets/common_widgets.dart';
import '../data/vehicle_api.dart';
import '../data/vehicle_models.dart';
import '../widgets/vehicle_widgets.dart';

const kMaxVehicles = 3; // same limit as the API

/// SCRUM-48 / SCRUM-56: "My vehicles" with status badges and the active toggle.
class VehicleListScreen extends StatefulWidget {
  const VehicleListScreen({super.key, required this.api});
  final VehicleApi api;

  @override
  State<VehicleListScreen> createState() => _VehicleListScreenState();
}

class _VehicleListScreenState extends State<VehicleListScreen> {
  late Future<List<Vehicle>> _future = widget.api.myVehicles();

  Future<void> _reload() async {
    final future = widget.api.myVehicles();
    setState(() {
      _future = future;
    });
    await future.catchError((_) => <Vehicle>[]);
  }

  Future<void> _open(String route) async {
    await Navigator.of(context).pushNamed(route);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Vehicle>>(
      future: _future,
      builder: (context, snap) {
        final loaded = snap.connectionState == ConnectionState.done && !snap.hasError;
        return Scaffold(
          appBar: AppBar(title: const Text('My vehicles')),
          floatingActionButton: loaded && snap.data!.length < kMaxVehicles
              ? FloatingActionButton.extended(
                  onPressed: () => _open('/vehicles/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Add vehicle'),
                )
              : null,
          body: snap.connectionState != ConnectionState.done
              ? const Center(child: CircularProgressIndicator())
              : snap.hasError
                  ? ErrorView(error: snap.error!, onRetry: _reload)
                  : RefreshIndicator(onRefresh: _reload, child: _list(snap.data!)),
        );
      },
    );
  }

  Widget _list(List<Vehicle> vehicles) {
    if (vehicles.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 120),
        EmptyView(icon: Icons.directions_car_outlined, message: 'No vehicles yet. Tap "Add vehicle" to register one.'),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        for (final v in vehicles) _VehicleCard(api: widget.api, vehicle: v, onOpen: _open, onChanged: _reload),
        if (vehicles.length >= kMaxVehicles)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('You can register up to 3 vehicles.', textAlign: TextAlign.center),
          ),
      ],
    );
  }
}

class _VehicleCard extends StatefulWidget {
  const _VehicleCard({required this.api, required this.vehicle, required this.onOpen, required this.onChanged});
  final VehicleApi api;
  final Vehicle vehicle;
  final Future<void> Function(String route) onOpen;
  final Future<void> Function() onChanged;

  @override
  State<_VehicleCard> createState() => _VehicleCardState();
}

class _VehicleCardState extends State<_VehicleCard> {
  bool _saving = false;

  Future<void> _toggle(bool value) async {
    setState(() => _saving = true);
    try {
      await widget.api.setActive(widget.vehicle.id, value);
      if (!mounted) return;
      showSnack(context, value ? 'Vehicle activated' : 'Vehicle deactivated');
      await widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(v.plateNumber, style: text.titleLarge)),
                StatusBadge(v.verificationStatus),
              ],
            ),
            const SizedBox(height: 4),
            Text('${v.title} · ${v.color} · ${v.vehicleType}'),
            const SizedBox(height: 4),
            Text(
              '${v.passengerSeats} sellable seats (of ${v.totalSeats})'
              '${v.cargoCapacityKg > 0 ? ' · cargo ${v.cargoCapacityKg} kg / ${v.cargoVolumeL} L' : ''}',
              style: text.bodySmall,
            ),
            if (v.verificationStatus == 'REJECTED' && v.rejectionReason != null) ...[
              const SizedBox(height: 6),
              Text('Rejected: ${v.rejectionReason}', style: TextStyle(color: Colors.red.shade700)),
            ],
            const Divider(height: 20),
            Row(
              children: [
                const Text('Active'),
                _saving
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : Switch(value: v.isActive, onChanged: _toggle),
                const Spacer(),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => widget.onOpen('/vehicles/${v.id}/edit'),
                ),
                IconButton(
                  tooltip: 'Documents',
                  icon: const Icon(Icons.folder_outlined),
                  onPressed: () => widget.onOpen('/vehicles/${v.id}/documents'),
                ),
                IconButton(
                  tooltip: 'Verification',
                  icon: const Icon(Icons.verified_outlined),
                  onPressed: () => widget.onOpen('/vehicles/${v.id}/verification'),
                ),
              ],
            ),
            if (!v.isUsableForTrips)
              Text(
                'This vehicle cannot be used for trips until it is approved and active.',
                style: text.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
