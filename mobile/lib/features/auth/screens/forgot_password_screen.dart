import 'package:flutter/material.dart';

import '../../../core/auth_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../widgets/auth_widgets.dart';
import 'reset_password_screen.dart';

/// Asks for the phone number. Returns true once the password has been changed.
class ForgotPasswordScreen extends StatefulWidget {
  final AuthService auth;
  final String initialPhone;
  const ForgotPasswordScreen({super.key, required this.auth, this.initialPhone = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: widget.initialPhone);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final phone = _phone.text.trim();
    try {
      await widget.auth.forgotPassword(phone);
      if (!mounted) return;
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => ResetPasswordScreen(auth: widget.auth, phone: phone)),
      );
      if (changed == true && mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPage(
      title: 'Forgot your password?',
      subtitle: 'Enter your mobile number. If it has an account, we will text it a reset code.',
      children: [
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(labelText: 'Mobile number', hintText: '0771234567'),
            validator: validatePhone,
            onFieldSubmitted: (_) => _busy ? null : _submit(),
          ),
        ),
        const SizedBox(height: 20),
        AuthError(_error),
        BusyButton(busy: _busy, onPressed: _submit, label: 'Send code'),
      ],
    );
  }
}
