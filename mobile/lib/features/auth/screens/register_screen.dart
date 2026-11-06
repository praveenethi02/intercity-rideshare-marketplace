import 'package:flutter/material.dart';

import '../../../core/auth_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../widgets/auth_widgets.dart';
import 'verify_phone_screen.dart';

/// The roles a user can pick. Same as SELECTABLE_ROLES in the backend.
const _roles = {
  'PASSENGER': 'Passenger',
  'DRIVER': 'Driver',
  'CARGO_CUSTOMER': 'Cargo',
};

class RegisterScreen extends StatefulWidget {
  final AuthService auth;
  final void Function(AuthService auth) onSignedIn;
  const RegisterScreen({super.key, required this.auth, required this.onSignedIn});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _role = 'PASSENGER';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final phone = _phone.text.trim();
    final email = _email.text.trim();
    try {
      await widget.auth.register(
        fullName: _name.text.trim(),
        phone: phone,
        email: email.isEmpty ? null : email,
        password: _password.text,
        role: _role,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerifyPhoneScreen(auth: widget.auth, phone: phone, onSignedIn: widget.onSignedIn),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = authErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPage(
      title: 'Create an account',
      subtitle: 'We will text a code to confirm your mobile number.',
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('I want to join as', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final role in _roles.entries) ButtonSegment(value: role.key, label: Text(role.value)),
                ],
                selected: {_role},
                onSelectionChanged: (selected) => setState(() => _role = selected.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                autofillHints: const [AutofillHints.name],
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) {
                  final name = (v ?? '').trim();
                  if (name.length < 2) return 'Enter your full name';
                  return name.length > 120 ? 'Use 120 characters or fewer' : null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Mobile number', hintText: '0771234567'),
                validator: validatePhone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email (optional)'),
                validator: (v) {
                  final email = (v ?? '').trim();
                  return email.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
                      ? null
                      : 'Enter a valid email address';
                },
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _password,
                autofillHints: const [AutofillHints.newPassword],
                validator: validateNewPassword,
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _confirm,
                label: 'Confirm password',
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) => v == _password.text ? null : 'The passwords do not match',
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        AuthError(_error),
        BusyButton(busy: _busy, onPressed: _submit, label: 'Create account'),
      ],
    );
  }
}
