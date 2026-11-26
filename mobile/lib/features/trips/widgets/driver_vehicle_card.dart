import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/common_widgets.dart';
import '../models/driver_vehicle.dart';
import 'search_result_card.dart' show fitBadge;

/// Who drives and in which vehicle (SCRUM-70). The driver profile loads on its own, so if it fails
/// the rest of the screen still works.
class DriverVehicleCard extends StatefulWidget {
  final Future<DriverPublicProfile> Function() loadDriver;

  /// Null when the server did not send it.
  final TripVehicle? vehicle;

  const DriverVehicleCard({super.key, required this.loadDriver, required this.vehicle});

  @override
  State<DriverVehicleCard> createState() => _DriverVehicleCardState();
}

// Kept alive so that scrolling away in a ListView does not load the profile again.
class _DriverVehicleCardState extends State<DriverVehicleCard> with AutomaticKeepAliveClientMixin {
  late Future<DriverPublicProfile> _driver = widget.loadDriver();

  @override
  bool get wantKeepAlive => true;

  void _retry() => setState(() {
        _driver = widget.loadDriver();
      });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FutureBuilder<DriverPublicProfile>(
          future: _driver,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const _DriverLoading();
            if (snap.hasError) return _DriverError(onRetry: _retry);
            return _DriverDetails(driver: snap.data!);
          },
        ),
        const Divider(height: AppSpacing.xl),
        _VehicleDetails(vehicle: widget.vehicle),
      ]),
    );
  }
}

class _DriverLoading extends StatelessWidget {
  const _DriverLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading driver',
      child: const Row(children: [
        SkeletonBox(width: 56, height: 56, radius: AppRadius.pill),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: 120, height: 18),
            SizedBox(height: AppSpacing.sm),
            SkeletonBox(width: 80),
          ]),
        ),
      ]),
    );
  }
}

class _DriverError extends StatelessWidget {
  final VoidCallback onRetry;
  const _DriverError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'Could not load the driver details.',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
      ),
      TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
    ]);
  }
}

class _DriverDetails extends StatelessWidget {
  final DriverPublicProfile driver;
  const _DriverDetails({required this.driver});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      Row(children: [
        _DriverPhoto(url: driver.photoUrl),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(driver.fullName, style: theme.textTheme.titleMedium),
            if (driver.verified) ...[
              const SizedBox(height: AppSpacing.xs),
              fitBadge(const AppBadge('Verified driver', tone: StatusTone.success, icon: Icons.verified_outlined)),
            ],
          ]),
        ),
      ]),
      const SizedBox(height: AppSpacing.sm),
      InfoRow(icon: Icons.star_outline, label: 'Rating', value: driver.ratingLabel),
      InfoRow(icon: Icons.done_all, label: 'Completed trips', value: '${driver.completedTrips}'),
    ]);
  }
}

class _DriverPhoto extends StatelessWidget {
  final String? url;
  const _DriverPhoto({required this.url});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasPhoto = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: 28,
      backgroundColor: scheme.surfaceContainerHighest,
      // The icon below stays visible while the photo loads and if it cannot be shown.
      foregroundImage: hasPhoto ? NetworkImage(url!) : null,
      onForegroundImageError: hasPhoto ? (_, __) {} : null,
      child: Icon(Icons.person, size: 32, color: scheme.onSurfaceVariant),
    );
  }
}

class _VehicleDetails extends StatelessWidget {
  final TripVehicle? vehicle;
  const _VehicleDetails({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    if (v == null) {
      return const InfoRow(icon: Icons.directions_car_outlined, label: 'Vehicle', value: 'Not available');
    }
    return Column(children: [
      InfoRow(icon: Icons.category_outlined, label: 'Type', value: v.typeLabel),
      InfoRow(icon: Icons.directions_car_outlined, label: 'Vehicle', value: '${v.make} ${v.model}'),
      InfoRow(icon: Icons.event_outlined, label: 'Year', value: '${v.year}'),
      InfoRow(icon: Icons.palette_outlined, label: 'Colour', value: v.color),
      if (v.plateNumber != null) InfoRow(icon: Icons.pin_outlined, label: 'Plate number', value: v.plateNumber!),
    ]);
  }
}
