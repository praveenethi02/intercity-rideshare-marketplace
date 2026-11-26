import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/vehicle_api.dart';
import '../data/vehicle_models.dart';
import '../widgets/vehicle_widgets.dart';

const kMaxVehicles = 3; // same limit as the API

/// An icon for each vehicle type.
IconData vehicleTypeIcon(String type) => switch (type) {
      'MOTORBIKE' => Icons.two_wheeler,
      'THREE_WHEELER' => Icons.electric_rickshaw,
      'VAN' || 'MINIBUS' => Icons.airport_shuttle,
      'BUS' => Icons.directions_bus,
      'PICKUP' || 'LORRY' => Icons.local_shipping,
      _ => Icons.directions_car,
    };

/// SCRUM-48 / SCRUM-56 / SCRUM-300: "My vehicles" with status badges and the active toggle.
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
              ? const SkeletonList(count: 2)
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
    final usable = vehicles.where((v) => v.isUsableForTrips).length;
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return ListView(
      // Room at the bottom so the Add vehicle button does not cover the last card.
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
      children: [
        Text(
          '${vehicles.length} of $kMaxVehicles vehicles · $usable ready for trips',
          style: muted,
        ),
        const SizedBox(height: AppSpacing.md),
        for (final v in vehicles)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _VehicleCard(api: widget.api, vehicle: v, onOpen: _open, onChanged: _reload),
          ),
        if (vehicles.length >= kMaxVehicles)
          Text('You can register up to $kMaxVehicles vehicles.', textAlign: TextAlign.center, style: muted),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final brand = AppStatusColors.of(context, StatusTone.info);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: brand.background, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Icon(vehicleTypeIcon(v.vehicleType), color: brand.foreground),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '${v.typeLabel} · ${v.color}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    StatusBadge(v.verificationStatus),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _fit(_Plate(v.plateNumber)),
              _fit(AppBadge(
                '${v.passengerSeats} passenger ${v.passengerSeats == 1 ? 'seat' : 'seats'}',
                icon: Icons.event_seat_outlined,
              )),
              if (v.cargoCapacityKg > 0)
                _fit(AppBadge('Cargo ${v.cargoCapacityKg} kg', icon: Icons.inventory_2_outlined)),
            ],
          ),
          if (v.verificationStatus == 'REJECTED' && v.rejectionReason != null)
            _Notice(tone: StatusTone.danger, icon: Icons.error_outline, text: 'Rejected: ${v.rejectionReason}'),
          if (!v.isUsableForTrips)
            const _Notice(
              tone: StatusTone.warning,
              icon: Icons.info_outline,
              text: 'This vehicle cannot be used for trips until it is approved and active.',
            ),
          const Divider(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(child: Text('Active', style: theme.textTheme.titleSmall)),
              _saving
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : Switch(value: v.isActive, onChanged: _toggle),
            ],
          ),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              TextButton.icon(
                onPressed: () => widget.onOpen('/vehicles/${v.id}/edit'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: () => widget.onOpen('/vehicles/${v.id}/documents'),
                icon: const Icon(Icons.folder_outlined),
                label: const Text('Documents'),
              ),
              TextButton.icon(
                onPressed: () => widget.onOpen('/vehicles/${v.id}/verification'),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Verification'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shrinks a badge that is wider than the card (a narrow screen or large text) instead of overflowing.
Widget _fit(Widget badge) => FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: badge);

/// The number plate, drawn like a plate so it is easy to spot.
class _Plate extends StatelessWidget {
  const _Plate(this.number);
  final String number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        number,
        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1),
      ),
    );
  }
}

/// A tinted note inside the card, such as why the vehicle cannot be used yet.
class _Notice extends StatelessWidget {
  const _Notice({required this.tone, required this.icon, required this.text});
  final StatusTone tone;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppStatusColors.of(context, tone);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.foreground)),
          ),
        ],
      ),
    );
  }
}
