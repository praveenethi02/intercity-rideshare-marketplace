import 'package:flutter/material.dart';

import '../../core/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/common_widgets.dart';
import 'edit_profile_screen.dart';

/// The Account tab (SCRUM-298): who is signed in, editing the profile, and signing out.
class AccountScreen extends StatelessWidget {
  final AppUser user;
  final SaveProfile onSaveProfile;
  final Future<void> Function() onSignOut;

  /// Opens the Driver tab. Null for admins, who have no driver tab.
  final VoidCallback? onOpenDriver;
  
  /// Opens My bookings.
  final VoidCallback? onOpenBookings;

  
  /// Opens the people the user can still rate.
  final VoidCallback? onRateTrips;

  /// Opens the ratings the user received.
  final VoidCallback? onOpenRatings;

  const AccountScreen({
    super.key,
    required this.user,
    required this.onSaveProfile,
    required this.onSignOut,
    this.onOpenDriver,
    this.onOpenBookings,
    this.onRateTrips,
    this.onOpenRatings,
  });

  Future<void> _editProfile(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditProfileScreen(user: user, onSave: onSaveProfile)),
    );
    if (saved == true && context.mounted) showSnack(context, 'Profile updated');
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'Sign out?',
      message: 'You are signed in as ${user.fullName}.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (ok) await onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: AppSpacing.screen,
        children: [
          _ProfileHeader(user: user),
          if (onOpenBookings != null) ...[
            const SectionTitle('Trips'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.confirmation_number_outlined),
                title: const Text('My bookings'),
                subtitle: const Text('Your seats on upcoming and past trips'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onOpenBookings,
              ),
            ),
          ],
                    if (onRateTrips != null && onOpenRatings != null) ...[
            const SectionTitle('Ratings'),
            Card(
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.rate_review_outlined),
                  title: const Text('Rate your trips'),
                  subtitle: const Text('People from your completed trips'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onRateTrips,
                ),
                const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
                ListTile(
                  leading: const Icon(Icons.star_outline_rounded),
                  title: const Text('My ratings'),
                  subtitle: const Text('What others said about you'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenRatings,
                ),
              ]),
            ),
          ],
          const SectionTitle('Profile'),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Edit profile'),
                subtitle: const Text('Your name and email'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _editProfile(context),
              ),
              if (onOpenDriver != null) ...[
                const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(user.isDriver ? 'Driver profile' : 'Become a driver'),
                  subtitle: Text(user.isDriver ? 'Documents, earnings and trip history' : 'Earn from your empty seats'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenDriver,
                ),
              ],
            ]),
          ),
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.errorContainer),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Intercity Rideshare',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final AppUser user;
  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final email = user.email;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: colors.primaryContainer,
          child: Text(
            user.initials,
            style: theme.textTheme.headlineSmall?.copyWith(color: colors.onPrimaryContainer),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(user.fullName, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        AppBadge(
          user.roleLabel,
          tone: user.isDriver ? StatusTone.success : StatusTone.info,
          icon: user.isDriver ? Icons.directions_car : Icons.person,
        ),
        const SizedBox(height: AppSpacing.lg),
        _Detail(icon: Icons.phone_outlined, text: user.phone),
        if (email != null && email.isNotEmpty) _Detail(icon: Icons.mail_outline, text: email),
      ]),
    );
  }
}

class _Detail extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Detail({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }
}
