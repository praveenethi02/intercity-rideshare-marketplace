import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/auth_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../widgets/auth_widgets.dart';

/// Confirms the code sent to the phone. A correct code activates the account and signs the user in.
class VerifyPhoneScreen extends StatefulWidget {
  final AuthService auth;
  final String phone;
  final void Function(AuthService auth) onSignedIn;
  const VerifyPhoneScreen({super.key, required this.auth, required this.phone, required this.onSignedIn});

  @override
  State<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends State<VerifyPhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.verifyOtp(widget.phone, _code.text.trim());
      if (!mounted) return;
      // The home screen replaces the login screen, so remove the screens opened on top of it.
      Navigator.of(context).popUntil((route) => route.isFirst);
      widget.onSignedIn(widget.auth);
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
      title: 'Enter the code',
      subtitle: 'We sent a 6-digit code to ${widget.phone}. It expires in 5 minutes.',
      children: [
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            decoration: const InputDecoration(labelText: 'Code'),
            validator: validateOtp,
            onFieldSubmitted: (_) => _busy ? null : _submit(),
          ),
        ),
        const SizedBox(height: 20),
        AuthError(_error),
        BusyButton(busy: _busy, onPressed: _submit, label: 'Verify'),
        const SizedBox(height: 8),
        ResendCodeButton(
          onResend: () => widget.auth.resendOtp(widget.phone),
          onResult: (error) => setState(() => _error = error),
        ),
      ],
    );
  }
}
