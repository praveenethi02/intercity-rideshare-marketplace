import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/vehicle_api.dart';
import '../data/vehicle_models.dart';
import '../widgets/vehicle_widgets.dart';

const kMaxVehicles = 3; // same limit as the API

/// SCRUM-48 / SCRUM-56: "My vehicles" with status badges and the active toggle.
class VehicleListScreen extends ConsumerWidget {
  const VehicleListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicles = ref.watch(myVehiclesProvider);
    final count = vehicles.valueOrNull?.length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('My vehicles')),
      floatingActionButton: vehicles.hasValue && count < kMaxVehicles
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/vehicles/new');
                ref.invalidate(myVehiclesProvider);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add vehicle'),
            )
          : null,
      body: vehicles.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: apiErrorMessage(e), onRetry: () => ref.invalidate(myVehiclesProvider)),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(myVehiclesProvider.future),
          child: list.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 120),
                  Icon(Icons.directions_car_outlined, size: 64),
                  SizedBox(height: 12),
                  Center(child: Text('No vehicles yet. Tap "Add vehicle" to register one.')),
                ])
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  children: [
                    for (final v in list) _VehicleCard(vehicle: v),
                    if (list.length >= kMaxVehicles)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('You can register up to 3 vehicles.', textAlign: TextAlign.center),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _VehicleCard extends ConsumerStatefulWidget {
  const _VehicleCard({required this.vehicle});
  final Vehicle vehicle;

  @override
  ConsumerState<_VehicleCard> createState() => _VehicleCardState();
}

class _VehicleCardState extends ConsumerState<_VehicleCard> {
  bool _saving = false;

  Future<void> _toggle(bool value) async {
    setState(() => _saving = true);
    try {
      await ref.read(vehicleApiProvider).setActive(widget.vehicle.id, value);
      ref.invalidate(myVehiclesProvider);
      if (mounted) showSnack(context, value ? 'Vehicle activated' : 'Vehicle deactivated');
    } catch (e) {
      if (mounted) showSnack(context, apiErrorMessage(e), error: true);
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
                  onPressed: () => context.push('/vehicles/${v.id}/edit'),
                ),
                IconButton(
                  tooltip: 'Documents',
                  icon: const Icon(Icons.folder_outlined),
                  onPressed: () => context.push('/vehicles/${v.id}/documents'),
                ),
                IconButton(
                  tooltip: 'Verification',
                  icon: const Icon(Icons.verified_outlined),
                  onPressed: () => context.push('/vehicles/${v.id}/verification'),
                ),
              ],
            ),
            if (!v.isActive || v.verificationStatus != 'APPROVED')
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
