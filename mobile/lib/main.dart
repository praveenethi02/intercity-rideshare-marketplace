import 'package:flutter/material.dart';

import 'core/app_services.dart';
import 'core/auth_service.dart';
import 'core/formatters.dart';
import 'features/trips/trips.dart';

/// Runs the Trips & Routes feature against the real backend.
/// Sign in with a phone and password registered through the auth API.
/// Member 1's own login/registration screens can replace [LoginScreen] later.
void main() => runApp(const RideshareApp());

/// Settings that come from the vehicles module once it exists.
class DriverVehicle {
  final String vehicleId;
  final int seatCapacity;
  const DriverVehicle(this.vehicleId, this.seatCapacity);
}

class RideshareApp extends StatefulWidget {
  const RideshareApp({super.key});
  @override
  State<RideshareApp> createState() => _RideshareAppState();
}

class _RideshareAppState extends State<RideshareApp> {
  AuthService? _auth;
  TripRepository? _trips;
  DriverVehicle? _vehicle;

  void _signedIn(AuthService auth, DriverVehicle? vehicle) => setState(() {
        _auth = auth;
        _trips = TripRepository(auth.api);
        _vehicle = vehicle;
      });

  Future<void> _signOut() async {
    await _auth?.logout();
    setState(() {
      _auth = null;
      _trips = null;
      _vehicle = null;
    });
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
              driverVehicleId: _vehicle?.vehicleId,
              vehicleSeatCapacity: _vehicle?.seatCapacity,
              onBookSegment: _demoBookingHandler,
              child: child!,
            ),
      home: user == null
          ? LoginScreen(onSignedIn: _signedIn)
          : HomeShell(user: user, onSignOut: _signOut),
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
  final Future<void> Function() onSignOut;
  const HomeShell({super.key, required this.user, required this.onSignOut});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final isDriver = widget.user.isDriver;
    final pages = isDriver ? const [DriverTripsScreen(), SearchTripsScreen()] : const [SearchTripsScreen()];
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

class LoginScreen extends StatefulWidget {
  final void Function(AuthService auth, DriverVehicle? vehicle) onSignedIn;
  const LoginScreen({super.key, required this.onSignedIn});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  // Android emulator: 10.0.2.2 is your computer. iOS simulator: use localhost.
  final _baseUrl = TextEditingController(text: 'http://10.0.2.2:4000/api/v1');
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _vehicleId = TextEditingController(text: '00000000-0000-4000-8000-000000000001');
  int _seatCapacity = 5;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _baseUrl.dispose();
    _phone.dispose();
    _password.dispose();
    _vehicleId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = AuthService(_baseUrl.text.trim().replaceAll(RegExp(r'/+$'), ''));
    try {
      final user = await auth.login(_phone.text.trim(), _password.text);
      if (!mounted) return;
      widget.onSignedIn(auth, user.isDriver ? DriverVehicle(_vehicleId.text.trim(), _seatCapacity) : null);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Mobile number', hintText: '0771234567'),
            validator: (v) => (v == null || v.trim().length < 9) ? 'Enter your mobile number' : null,
          ),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sign in'),
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Developer settings'),
            children: [
              TextFormField(
                controller: _baseUrl,
                decoration: const InputDecoration(
                  labelText: 'API base URL',
                  helperText: 'Android emulator: 10.0.2.2 · iOS simulator: localhost · phone: your computer\'s Wi-Fi IP',
                ),
                validator: (v) => (v == null || !v.startsWith('http')) ? 'Enter http(s)://…' : null,
              ),
              TextFormField(
                controller: _vehicleId,
                decoration: const InputDecoration(
                  labelText: 'Vehicle ID (drivers)',
                  helperText: 'Any UUID until the vehicles module exists',
                ),
                validator: (v) => RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(v?.trim() ?? '') ? null : 'Enter a UUID',
              ),
              Row(children: [
                const Expanded(child: Text('Vehicle seats (incl. driver)')),
                IconButton(
                  onPressed: _seatCapacity > 2 ? () => setState(() => _seatCapacity--) : null,
                  icon: const Icon(Icons.remove),
                ),
                Text('$_seatCapacity'),
                IconButton(
                  onPressed: _seatCapacity < 15 ? () => setState(() => _seatCapacity++) : null,
                  icon: const Icon(Icons.add),
                ),
              ]),
            ],
          ),
        ]),
      ),
    );
  }
}
