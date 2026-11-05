import 'package:flutter/material.dart';

import '../../../core/widgets/common_widgets.dart';
import '../data/driver_repository.dart';
import '../models/driver_models.dart';
import '../widgets/driver_widgets.dart';
import 'become_driver_screen.dart';
import 'driver_documents_screen.dart';
import 'driver_earnings_screen.dart';
import 'driver_profile_screen.dart';
import 'driver_trip_history_screen.dart';
import 'driver_verification_screen.dart';

/// The Driver tab: an invitation to register, or the driver's status and tools.
class DriverHomeScreen extends StatefulWidget {
  final DriverRepository repository;

  /// Lets the app switch this user to the driver view after they register.
  final VoidCallback? onBecameDriver;

  const DriverHomeScreen({super.key, required this.repository, this.onBecameDriver});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  late Future<DriverProfile?> _future = widget.repository.myProfile();

  Future<void> _reload() async {
    final future = widget.repository.myProfile();
    setState(() => _future = future);
    await future.then((_) {}, onError: (_) {});
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
  }

  Future<void> _register() async {
    final registered = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BecomeDriverScreen(repository: widget.repository)),
    );
    if (registered != true) return;
    widget.onBecameDriver?.call();
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Driver')),
      body: FutureBuilder<DriverProfile?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          final driver = snap.data;
          if (driver == null) {
            return EmptyView(
              icon: Icons.drive_eta_outlined,
              message: 'Earn from your empty seats.\nRegister as a driver to start offering trips.',
              action: FilledButton(onPressed: _register, child: const Text('Become a driver')),
            );
          }
          return _dashboard(driver);
        },
      ),
    );
  }

  Widget _dashboard(DriverProfile driver) {
    final repository = widget.repository;
    final uploaded = driverDocumentTypes.where((t) => driver.documents.any((d) => d.type == t)).length;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        _StatusCard(driver: driver, uploaded: uploaded),
        const SizedBox(height: 8),
        _ToolTile(
          icon: Icons.folder_outlined,
          title: 'My documents',
          subtitle: '$uploaded of ${driverDocumentTypes.length} uploaded',
          onTap: () => _open(DriverDocumentsScreen(repository: repository)),
        ),
        _ToolTile(
          icon: Icons.verified_user_outlined,
          title: 'Verification status',
          subtitle: 'See where your review stands',
          onTap: () => _open(DriverVerificationScreen(repository: repository)),
        ),
        _ToolTile(
          icon: Icons.person_outline,
          title: 'Driver profile',
          subtitle: 'Licence, contact details and rating',
          onTap: () => _open(DriverProfileScreen(repository: repository, driver: driver)),
        ),
        _ToolTile(
          icon: Icons.payments_outlined,
          title: 'Earnings',
          subtitle: 'Your earnings summary',
          onTap: () => _open(DriverEarningsScreen(repository: repository)),
        ),
        _ToolTile(
          icon: Icons.history,
          title: 'Trip history',
          subtitle: '${driver.completedTrips} completed',
          onTap: () => _open(DriverTripHistoryScreen(repository: repository)),
        ),
      ]),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final DriverProfile driver;
  final int uploaded;
  const _StatusCard({required this.driver, required this.uploaded});

  String get _chipStatus {
    if (driver.accountStatus != 'ACTIVE') return driver.accountStatus;
    if (driver.verification == 'PENDING' && uploaded < driverDocumentTypes.length) return driverStatusDocumentsNeeded;
    return driver.verification;
  }

  String get _message {
    if (driver.accountStatus != 'ACTIVE') return 'Your driver account is not active. Contact support for help.';
    if (driver.verification == 'APPROVED') return 'You can offer trips once you have an approved vehicle.';
    if (driver.verification == 'REJECTED') return 'Your application needs changes before it can be approved.';
    final missing = driverDocumentTypes.length - uploaded;
    if (missing > 0) return 'Upload $missing more ${missing == 1 ? 'document' : 'documents'} to send your application for review.';
    return 'An admin is reviewing your documents.';
  }

  @override
  Widget build(BuildContext context) {
    final reason = driver.rejectionReason;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Verification', style: Theme.of(context).textTheme.titleMedium)),
            DriverStatusChip(_chipStatus),
          ]),
          const SizedBox(height: 8),
          Text(_message),
          if (reason != null) ...[
            const SizedBox(height: 8),
            Text('Reason from the admin: $reason', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ToolTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
