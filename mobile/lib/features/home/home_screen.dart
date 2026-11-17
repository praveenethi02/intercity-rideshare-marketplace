import 'package:flutter/material.dart';

import '../../core/auth_service.dart';
import '../trips/data/towns.dart';
import '../trips/models/search.dart';
import '../trips/models/trip.dart';
import '../trips/screens/passenger/search_results_screen.dart';

/// Routes shown as shortcuts. Each name must be in kTowns.
const popularRoutes = [
  ('Colombo Fort', 'Kandy'),
  ('Colombo Fort', 'Galle'),
  ('Kandy', 'Kurunegala'),
  ('Colombo Fort', 'Jaffna'),
];

/// "Good morning" and so on, from the hour of [now].
String greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// The first tab: a greeting, a search shortcut, popular routes and the driver invitation.
class HomeScreen extends StatelessWidget {
  final AppUser user;

  /// Opens the Find a ride tab.
  final VoidCallback onFindRide;

  /// Opens the Driver tab, to register or to manage the driver profile.
  final VoidCallback onOpenDriver;

  /// Opens My trips. Null when the user is not a driver.
  final VoidCallback? onOpenMyTrips;

  /// Lets tests fix the time for the greeting.
  final DateTime Function() clock;

  const HomeScreen({
    super.key,
    required this.user,
    required this.onFindRide,
    required this.onOpenDriver,
    this.onOpenMyTrips,
    this.clock = DateTime.now,
  });

  void _searchRoute(BuildContext context, String from, String to) {
    TripStop town(String name) => kTowns.firstWhere((t) => t.name == name);
    final tomorrow = clock().add(const Duration(days: 1));
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchResultsScreen(
        query: SearchQuery(from: town(from), to: town(to), date: DateTime(tomorrow.year, tomorrow.month, tomorrow.day)),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Header(user: user, greeting: greetingFor(clock()), onFindRide: onFindRide),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            // Same height for all three, even when a label wraps to two lines.
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: _QuickAction(icon: Icons.search, label: 'Find a ride', onTap: onFindRide),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: onOpenMyTrips == null
                      ? _QuickAction(icon: Icons.badge_outlined, label: 'Become a driver', onTap: onOpenDriver)
                      : _QuickAction(icon: Icons.directions_car, label: 'My trips', onTap: onOpenMyTrips!),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: _QuickAction(icon: Icons.local_shipping_outlined, label: 'Send a parcel', soon: true),
                ),
              ]),
            ),
          ),
          const _SectionHeader('Popular routes'),
          SizedBox(
            height: 112,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: popularRoutes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final (from, to) = popularRoutes[i];
                return _RouteCard(from: from, to: to, onTap: () => _searchRoute(context, from, to));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: user.isDriver
                ? _Banner(
                    icon: Icons.route,
                    title: 'Ready for your next trip?',
                    message: 'Publish a trip and let passengers book or bid for your empty seats.',
                    action: 'Open my trips',
                    onPressed: onOpenMyTrips ?? onOpenDriver,
                  )
                : _Banner(
                    icon: Icons.payments_outlined,
                    title: 'Earn from your empty seats',
                    message: 'Driving between cities anyway? Register as a driver and share the cost of your trip.',
                    action: 'Become a driver',
                    onPressed: onOpenDriver,
                  ),
          ),
          const _SectionHeader('Why travel with us'),
          const _Feature(
            icon: Icons.gavel_outlined,
            title: 'Name your price',
            message: 'Book at a fixed price, or bid for a seat on auction trips.',
          ),
          const _Feature(
            icon: Icons.verified_user_outlined,
            title: 'Verified drivers',
            message: 'We check every driver\'s licence, identity and vehicle before their first trip.',
          ),
          const _Feature(
            icon: Icons.alt_route,
            title: 'Join on the way',
            message: 'Get on or off at any stop along the route, not just the start and the end.',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final AppUser user;
  final String greeting;
  final VoidCallback onFindRide;
  const _Header({required this.user, required this.greeting, required this.onFindRide});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final onPrimary = colors.onPrimary;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primary, colors.onPrimaryContainer],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '$greeting, ${user.greetingName}',
                    style: theme.textTheme.headlineSmall?.copyWith(color: onPrimary, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Where are you travelling today?',
                    style: theme.textTheme.bodyMedium?.copyWith(color: onPrimary.withValues(alpha: 0.85)),
                  ),
                ]),
              ),
              CircleAvatar(
                radius: 22,
                backgroundColor: onPrimary.withValues(alpha: 0.2),
                child: Text(
                  user.greetingName.characters.first.toUpperCase(),
                  style: theme.textTheme.titleMedium?.copyWith(color: onPrimary, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Material(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onFindRide,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(children: [
                    Icon(Icons.search, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Where to?',
                        style: theme.textTheme.titleMedium?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                    Icon(Icons.arrow_forward, color: colors.primary),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool soon;
  const _QuickAction({required this.icon, required this.label, this.onTap, this.soon = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = onTap != null;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: enabled ? colors.primaryContainer : colors.surfaceContainerHighest,
              child: Icon(icon, color: enabled ? colors.onPrimaryContainer : colors.outline),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: theme.textTheme.labelLarge?.copyWith(color: enabled ? null : colors.outline),
            ),
            if (soon) Text('Coming soon', style: theme.textTheme.labelSmall?.copyWith(color: colors.outline)),
          ]),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final String from;
  final String to;
  final VoidCallback onTap;
  const _RouteCard({required this.from, required this.to, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      width: 168,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Stop(icon: Icons.trip_origin, name: from),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: SizedBox(height: 10, child: VerticalDivider(width: 2, color: colors.outlineVariant)),
              ),
              _Stop(icon: Icons.place, name: to),
              const Spacer(),
              Text('Tomorrow · See rides', style: theme.textTheme.labelMedium?.copyWith(color: colors.primary)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Stop extends StatelessWidget {
  final IconData icon;
  final String name;
  const _Stop({required this.icon, required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      Icon(icon, size: 18, color: theme.colorScheme.primary),
      const SizedBox(width: 6),
      Expanded(
        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
      ),
    ]);
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onPressed;
  const _Banner({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: colors.surface,
          child: Icon(icon, color: colors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSecondaryContainer)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onPressed, child: Text(action)),
          ]),
        ),
      ]),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _Feature({required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        child: Icon(icon, color: colors.onPrimaryContainer),
      ),
      title: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      subtitle: Text(message),
    );
  }
}
