import 'package:flutter/material.dart';

import 'core/app_services.dart';
import 'core/auth_service.dart';
import 'core/formatters.dart';
import 'features/auth/auth.dart';
import 'features/driver/driver.dart';
import 'features/trips/trips.dart';
import 'features/vehicle/vehicle.dart';

/// Runs the app against the real backend.
void main() => runApp(const RideshareApp());

class RideshareApp extends StatefulWidget {
  const RideshareApp({super.key});
  @override
  State<RideshareApp> createState() => _RideshareAppState();
}

class _RideshareAppState extends State<RideshareApp> {
  AuthService? _auth;
  TripRepository? _trips;
  DriverRepository? _drivers;
  VehicleApi? _vehicles;
  Vehicle? _vehicle;

  void _signedIn(AuthService auth) {
    setState(() {
      _auth = auth;
      _trips = TripRepository(auth.api);
      _drivers = DriverRepository(auth.api);
      _vehicles = VehicleApi(auth.api);
      _vehicle = null;
    });
    if (auth.user?.isDriver ?? false) _checkDriverVehicle();
  }

  Future<void> _signOut() async {
    await _auth?.logout();
    setState(() {
      _auth = null;
      _trips = null;
      _drivers = null;
      _vehicles = null;
      _vehicle = null;
    });
  }

  /// Loads the driver's approved vehicle for the trips screens. Returns null when there is one,
  /// or a message that explains why the driver cannot create a trip.
  Future<String?> _checkDriverVehicle() async {
    final api = _vehicles;
    if (api == null) return 'Sign in again to load your vehicles.';
    List<Vehicle>? vehicles;
    Object? failure;
    try {
      vehicles = await api.myVehicles();
    } catch (e) {
      failure = e;
    }
    // The driver may have signed out while this was loading.
    if (!mounted || !identical(api, _vehicles)) return 'Sign in again to load your vehicles.';
    final vehicle = vehicles == null ? null : usableVehicle(vehicles);
    setState(() => _vehicle = vehicle);
    if (vehicles == null) return 'Could not load your vehicles: $failure';
    return vehicle == null ? noUsableVehicleMessage(vehicles) : null;
  }

  /// Registering makes this user a driver on the server, so the app shows the driver tabs too.
  void _becameDriver() {
    final auth = _auth;
    final user = auth?.user;
    if (auth == null || user == null) return;
    setState(() => auth.user = AppUser(id: user.id, fullName: user.fullName, phone: user.phone, role: 'DRIVER'));
    _checkDriverVehicle();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth?.user;
    return MaterialApp(
      title: 'Intercity Rideshare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0B6E4F), useMaterial3: true),
      // AppServices sits above the Navigator so every pushed screen can use it.
      builder: (context, child) => _trips == null
          ? child!
          : AppServices(
              trips: _trips!,
              driverVehicleId: _vehicle?.id,
              // AppServices takes off the driver's own seat. The API limits a trip to the vehicle's
              // passengerSeats, which can be fewer than totalSeats - 1, so build the capacity from it.
              vehicleSeatCapacity: _vehicle == null ? null : _vehicle!.passengerSeats + 1,
              checkDriverVehicle: _checkDriverVehicle,
              onBookSegment: _demoBookingHandler,
              child: child!,
            ),
      onGenerateRoute: (settings) => _vehicles == null ? null : vehicleRoute(settings, _vehicles!),
      home: user == null
          ? LoginScreen(onSignedIn: _signedIn)
          : HomeShell(user: user, drivers: _drivers!, onSignOut: _signOut, onBecameDriver: _becameDriver),
    );
  }
}

/// Placeholder until the Booking / Auction modules plug in their screens.
Future<void> _demoBookingHandler(BuildContext context, SegmentSelection s) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.pricingMode == PricingMode.auction ? 'Bid (coming soon)' : 'Booking (coming soon)'),
      content: Text(
        'Stops ${s.fromStop} → ${s.toStop}\n'
        '${s.seats} seat(s) at ${formatLkr(s.pricePerSeatCents)} each\n\n'
        'The Booking / Auction module opens its screen here and calls reserveSeats on the server.',
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}

class HomeShell extends StatefulWidget {
  final AppUser user;
  final DriverRepository drivers;
  final Future<void> Function() onSignOut;
  final VoidCallback onBecameDriver;
  const HomeShell({
    super.key,
    required this.user,
    required this.drivers,
    required this.onSignOut,
    required this.onBecameDriver,
  });
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void didUpdateWidget(HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Becoming a driver adds "My trips" at the start, so stay on the same tab.
    if (widget.user.isDriver && !oldWidget.user.isDriver) _tab += 1;
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = widget.user.isDriver;
    final showDriverTab = widget.user.role != 'ADMIN';
    final pages = <Widget>[
      if (isDriver) const DriverTripsScreen(),
      const SearchTripsScreen(),
      if (showDriverTab) DriverHomeScreen(repository: widget.drivers, onBecameDriver: widget.onBecameDriver),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) async {
          if (i < pages.length) {
            setState(() => _tab = i);
            return;
          }
          final ok = await confirmSignOut(context, widget.user.fullName);
          if (ok) await widget.onSignOut();
        },
        destinations: [
          if (isDriver) const NavigationDestination(icon: Icon(Icons.directions_car), label: 'My trips'),
          const NavigationDestination(icon: Icon(Icons.search), label: 'Find a ride'),
          if (showDriverTab) const NavigationDestination(icon: Icon(Icons.badge_outlined), label: 'Driver'),
          const NavigationDestination(icon: Icon(Icons.logout), label: 'Sign out'),
        ],
      ),
    );
  }
}

Future<bool> confirmSignOut(BuildContext context, String name) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign out?'),
      content: Text('You are signed in as $name.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
      ],
    ),
  );
  return result ?? false;
}
