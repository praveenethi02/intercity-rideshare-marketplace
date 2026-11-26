import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'core/api_client.dart';
import 'core/app_services.dart';
import 'core/auth_service.dart';
import 'core/session_store.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/common_widgets.dart';
import 'features/auth/auth.dart';
import 'features/account/account_screen.dart';
import 'features/account/edit_profile_screen.dart' show SaveProfile;
import 'features/account/splash_screen.dart';
import 'features/bookings/bookings.dart';
import 'features/driver/driver.dart';
import 'features/home/home_screen.dart';
import 'features/ratings/ratings.dart';
import 'features/trips/trips.dart';
import 'features/vehicle/vehicle.dart';

/// Runs the app against the real backend.
void main() => runApp(const RideshareApp());

class RideshareApp extends StatefulWidget {
  final SessionStore store;

  /// Lets tests answer the API calls.
  final http.Client? httpClient;

  const RideshareApp({super.key, this.store = const SecureSessionStore(), this.httpClient});
  @override
  State<RideshareApp> createState() => _RideshareAppState();
}

class _RideshareAppState extends State<RideshareApp> {
  AuthService? _auth;
  TripRepository? _trips;
  DriverRepository? _drivers;
  VehicleApi? _vehicles;
  BookingApi? _bookings;
  RatingApi? _ratings;
  Vehicle? _vehicle;
  String? _baseUrl;
  bool _restoring = true;
  String? _restoreError;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  /// Signs the user back in if a refresh token was saved the last time the app ran.
  Future<void> _restoreSession() async {
    final saved = await widget.store.read();
    final baseUrl = saved.baseUrl;
    final refreshToken = saved.refreshToken;
    if (!mounted) return;
    _baseUrl = baseUrl;
    if (baseUrl == null || refreshToken == null) {
      setState(() => _restoring = false);
      return;
    }

    final auth = AuthService(baseUrl, httpClient: widget.httpClient, store: widget.store);
    try {
      await auth.restore(refreshToken);
      if (!mounted) return;
      setState(() => _restoring = false);
      _signedIn(auth);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        // An expired session goes to sign in. A temporary problem should not sign the user out.
        _restoreError = e.isTemporary ? e.message : null;
      });
    }
  }

  void _retryRestore() {
    setState(() {
      _restoring = true;
      _restoreError = null;
    });
    _restoreSession();
  }

  Future<void> _useAnotherAccount() async {
    await widget.store.clearToken();
    if (mounted) setState(() => _restoreError = null);
  }

  void _signedIn(AuthService auth) {
    setState(() {
      _auth = auth;
      _baseUrl = auth.baseUrl;
      _trips = TripRepository(auth.api);
      _drivers = DriverRepository(auth.api);
      _vehicles = VehicleApi(auth.api);
      _bookings = BookingApi(auth.api);
      _ratings = RatingApi(auth.api);
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
      _bookings = null;
      _ratings = null;
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

  /// Book on a FIXED-price trip opens the booking screens (SCRUM-304).
  /// Bidding on AUCTION trips comes in Sprint 3.
  Future<void> _bookSegment(BuildContext context, SegmentSelection selection) async {
    final api = _bookings;
    if (api == null) return;
    if (selection.pricingMode == PricingMode.auction) {
      showSnack(context, 'Bidding on auction trips is coming soon.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ConfirmBookingScreen(api: api, selection: selection)),
    );
  }

  /// Saves the profile, then rebuilds so Home and Account show the new name at once.
  Future<void> _saveProfile({required String firstName, required String lastName, required String email}) async {
    final auth = _auth;
    if (auth == null) return;
    await auth.updateProfile(firstName: firstName, lastName: lastName, email: email);
    if (mounted) setState(() {});
  }

  /// Registering makes this user a driver on the server, so the app shows the driver tabs too.
  void _becameDriver() {
    final auth = _auth;
    final user = auth?.user;
    if (auth == null || user == null) return;
    setState(() => auth.user = user.copyWith(role: 'DRIVER'));
    _checkDriverVehicle();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth?.user;
    return MaterialApp(
      title: 'Ride Share',
      debugShowCheckedModeBanner: false,
      // The shared theme from the Figma design system (SCRUM-296).
      theme: AppTheme.light,
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
              onBookSegment: _bookSegment,
              child: child!,
            ),
      onGenerateRoute: (settings) => _vehicles == null ? null : vehicleRoute(settings, _vehicles!),
      home: _home(user),
    );
  }

  Widget _home(AppUser? user) {
    if (user != null) {
      return HomeShell(
        user: user,
        drivers: _drivers!,
        onSignOut: _signOut,
        onBecameDriver: _becameDriver,
        onSaveProfile: _saveProfile,
        bookings: _bookings!,
        ratings: _ratings!,
      );
    }
    if (_restoring) return const SplashScreen();
    final error = _restoreError;
    if (error != null) {
      return Scaffold(
        body: SafeArea(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            ErrorView(error: error, onRetry: _retryRestore),
            TextButton(onPressed: _useAnotherAccount, child: const Text('Sign in with another account')),
          ]),
        ),
      );
    }
    return LoginScreen(
      onSignedIn: _signedIn,
      store: widget.store,
      initialBaseUrl: _baseUrl,
      httpClient: widget.httpClient,
    );
  }
}

class HomeShell extends StatefulWidget {
  final AppUser user;
  final DriverRepository drivers;
  final Future<void> Function() onSignOut;
  final VoidCallback onBecameDriver;
  final SaveProfile onSaveProfile;
  final BookingApi bookings;
  final RatingApi ratings;
  const HomeShell({
    super.key,
    required this.user,
    required this.drivers,
    required this.onSignOut,
    required this.onBecameDriver,
    required this.onSaveProfile,
    required this.bookings,
    required this.ratings,
  });
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void didUpdateWidget(HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Becoming a driver adds "My trips" after Home, so stay on the same tab.
    if (widget.user.isDriver && !oldWidget.user.isDriver && _tab >= 1) _tab += 1;
  }

  void _go(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final isDriver = widget.user.isDriver;
    final showDriverTab = widget.user.role != 'ADMIN';
    // Tab order: Home, My trips (drivers only), Find a ride, Driver (not for admins), Account.
    final myTripsTab = isDriver ? 1 : null;
    final searchTab = isDriver ? 2 : 1;
    final driverTab = showDriverTab ? searchTab + 1 : null;
    final accountTab = (driverTab ?? searchTab) + 1;
    final pages = <Widget>[
      HomeScreen(
        user: widget.user,
        onFindRide: () => _go(searchTab),
        onOpenDriver: () => _go(driverTab ?? searchTab),
        onOpenMyTrips: myTripsTab == null ? null : () => _go(myTripsTab),
        onOpenAccount: () => _go(accountTab),
      ),
      if (isDriver) const DriverTripsScreen(),
      const SearchTripsScreen(),
      if (showDriverTab) DriverHomeScreen(repository: widget.drivers, onBecameDriver: widget.onBecameDriver),
      AccountScreen(
        user: widget.user,
        onSaveProfile: widget.onSaveProfile,
        onSignOut: widget.onSignOut,
        onOpenDriver: driverTab == null ? null : () => _go(driverTab),
        onRateTrips: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => PendingRatingsScreen(api: widget.ratings)),
        ),
        onOpenRatings: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReceivedRatingsScreen(api: widget.ratings, userId: widget.user.id),
          ),
        ),
        onOpenBookings: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => MyBookingsScreen(api: widget.bookings)),
        ),
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          if (isDriver) const NavigationDestination(icon: Icon(Icons.directions_car), label: 'My trips'),
          const NavigationDestination(icon: Icon(Icons.search), label: 'Find a ride'),
          if (showDriverTab) const NavigationDestination(icon: Icon(Icons.badge_outlined), label: 'Driver'),
          const NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
