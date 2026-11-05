import 'package:flutter/material.dart';

import '../../../../core/app_services.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../models/trip.dart';
import '../../widgets/trip_widgets.dart';
import 'active_trip_screen.dart';
import 'create_trip_screen.dart';
import 'driver_trip_detail_screen.dart';
import 'saved_routes_screen.dart';

/// Driver home for trips: Upcoming / Active / Past tabs.
class DriverTripsScreen extends StatefulWidget {
  const DriverTripsScreen({super.key});

  @override
  State<DriverTripsScreen> createState() => _DriverTripsScreenState();
}

class _DriverTripsScreenState extends State<DriverTripsScreen> {
  late Future<List<Trip>> _future;

  @override
  void initState() {
    super.initState();
    _future = AppServices.of(context).trips.myTrips();
  }

  Future<void> _reload() async {
    final future = AppServices.of(context).trips.myTrips();
    setState(() => _future = future);
    await future.catchError((_) => <Trip>[]);
  }

  Future<void> _newTrip() async {
    final services = AppServices.of(context);
    if (services.driverVehicleId == null) {
      showSnack(context, 'Add a vehicle and wait for approval before creating trips.');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateTripScreen()));
    if (mounted) _reload();
  }

  Future<void> _open(Trip trip) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => trip.isActive ? ActiveTripScreen(tripId: trip.id) : DriverTripDetailScreen(tripId: trip.id),
    ));
    if (mounted) _reload();
  }

  Widget _list(List<Trip> trips, String emptyText, {bool newestFirst = false}) {
    final sorted = List<Trip>.of(trips)
      ..sort((a, b) => newestFirst
          ? b.departureTime.compareTo(a.departureTime)
          : a.departureTime.compareTo(b.departureTime));
    return RefreshIndicator(
      onRefresh: _reload,
      child: sorted.isEmpty
          ? ListView(children: [
              const SizedBox(height: 120),
              EmptyView(icon: Icons.directions_car_outlined, message: emptyText),
            ])
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 96),
              itemCount: sorted.length,
              itemBuilder: (_, i) => TripCard(trip: sorted[i], onTap: () => _open(sorted[i])),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My trips'),
          actions: [
            IconButton(
              tooltip: 'Saved routes',
              icon: const Icon(Icons.bookmarks_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SavedRoutesScreen()),
              ),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Upcoming'), Tab(text: 'Active'), Tab(text: 'Past')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _newTrip,
          icon: const Icon(Icons.add),
          label: const Text('New trip'),
        ),
        body: FutureBuilder<List<Trip>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
            final trips = snap.data!;
            return TabBarView(children: [
              _list(trips.where((t) => t.isUpcoming).toList(), 'No upcoming trips.\nTap "New trip" to offer seats.'),
              _list(trips.where((t) => t.isActive).toList(), 'No trip in progress.'),
              _list(trips.where((t) => t.isPast).toList(), 'No completed or cancelled trips yet.', newestFirst: true),
            ]);
          },
        ),
      ),
    );
  }
}
