import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/auth_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../widgets/auth_widgets.dart';

/// Sets a new password using the texted code. Returns true when it succeeds.
class ResetPasswordScreen extends StatefulWidget {
  final AuthService auth;
  final String phone;
  const ResetPasswordScreen({super.key, required this.auth, required this.phone});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
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
    try {
      await widget.auth.resetPassword(widget.phone, _code.text.trim(), _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = authErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPage(
      title: 'Choose a new password',
      subtitle: 'If ${widget.phone} has an account, we sent it a 6-digit code.',
      children: [
        Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _code,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Code'),
              validator: validateOtp,
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _password,
              label: 'New password',
              autofillHints: const [AutofillHints.newPassword],
              validator: validateNewPassword,
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _confirm,
              label: 'Confirm new password',
              autofillHints: const [AutofillHints.newPassword],
              validator: (v) => v == _password.text ? null : 'The passwords do not match',
              onSubmitted: (_) => _busy ? null : _submit(),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        AuthError(_error),
        BusyButton(busy: _busy, onPressed: _submit, label: 'Change password'),
        const SizedBox(height: 8),
        ResendCodeButton(
          onResend: () => widget.auth.forgotPassword(widget.phone),
          onResult: (error) => setState(() => _error = error),
        ),
      ],
    );
  }
}
