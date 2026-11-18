import 'package:flutter/material.dart';

import '../../core/auth_service.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/common_widgets.dart';
import '../auth/screens/register_screen.dart' show validatePersonName;
import '../auth/widgets/auth_widgets.dart' show AuthError, authErrorText;

/// Saves a new name and email. Throws when the server rejects them.
typedef SaveProfile = Future<void> Function({
  required String firstName,
  required String lastName,
  required String email,
});

/// Edits the first name, last name and email. Pops with true after a successful save.
class EditProfileScreen extends StatefulWidget {
  final AppUser user;
  final SaveProfile onSave;
  const EditProfileScreen({super.key, required this.user, required this.onSave});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _firstName = TextEditingController(text: widget.user.firstName);
  late final _lastName = TextEditingController(text: widget.user.lastName);
  late final _email = TextEditingController(text: widget.user.email ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_firstName, _lastName, _email]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        email: _email.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            TextFormField(
              controller: _firstName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'First name'),
              validator: (v) => validatePersonName(v, 'first name'),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _lastName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Last name'),
              validator: (v) => validatePersonName(v, 'last name'),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email (optional)'),
              validator: (v) {
                final email = (v ?? '').trim();
                return email.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
                    ? null
                    : 'Enter a valid email address';
              },
              onFieldSubmitted: (_) => _busy ? null : _save(),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              initialValue: widget.user.phone,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                helperText: 'Your mobile number signs you in, so it cannot be changed here.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            AuthError(_error),
            BusyButton(busy: _busy, onPressed: _save, label: 'Save changes'),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your first name is used to greet you on the Home screen.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
