import 'package:flutter/material.dart';

import '../../../core/auth_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../widgets/auth_widgets.dart';
import 'verify_phone_screen.dart';

/// Same rule as personName in the backend.
String? validatePersonName(String? value, String label) {
  final name = (value ?? '').trim();
  if (name.isEmpty) return 'Enter your $label';
  return name.length > 50 ? 'Use 50 characters or fewer' : null;
}

/// Everyone signs up as a passenger. Drivers register later from the Driver tab.
class RegisterScreen extends StatefulWidget {
  final AuthService auth;
  final void Function(AuthService auth) onSignedIn;
  const RegisterScreen({super.key, required this.auth, required this.onSignedIn});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_firstName, _lastName, _phone, _email, _password, _confirm]) {
      controller.dispose();
    }
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
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: phone,
        email: email.isEmpty ? null : email,
        password: _password.text,
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
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstName,
                    autofillHints: const [AutofillHints.givenName],
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'First name'),
                    validator: (v) => validatePersonName(v, 'first name'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lastName,
                    autofillHints: const [AutofillHints.familyName],
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Last name'),
                    validator: (v) => validatePersonName(v, 'last name'),
                  ),
                ),
              ]),
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
        const SizedBox(height: 12),
        Text(
          'Want to offer rides? After you sign up, open the Driver tab to register as a driver.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
