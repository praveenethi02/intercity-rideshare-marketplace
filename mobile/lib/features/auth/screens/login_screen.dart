import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/api_client.dart';
import '../../../core/auth_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../widgets/auth_widgets.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';
import 'verify_phone_screen.dart';

/// First screen of the app. Registration and password reset open from here.
class LoginScreen extends StatefulWidget {
  final void Function(AuthService auth) onSignedIn;

  /// Lets tests answer the API calls.
  final http.Client? httpClient;

  const LoginScreen({super.key, required this.onSignedIn, this.httpClient});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  // Android emulator: 10.0.2.2 is your computer. iOS simulator and web: use localhost.
  final _baseUrl = TextEditingController(text: kIsWeb ? 'http://localhost:4000/api/v1' : 'http://10.0.2.2:4000/api/v1');
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _baseUrl.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  AuthService? _createAuth() {
    final url = _baseUrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (!url.startsWith('http')) {
      setState(() => _error = 'Check the API base URL in Developer settings.');
      return null;
    }
    return AuthService(url, httpClient: widget.httpClient);
  }

  void _open(Widget Function(AuthService auth) screen) {
    final auth = _createAuth();
    if (auth == null) return;
    setState(() => _error = null);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen(auth)));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = _createAuth();
    if (auth == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.login(_phone.text.trim(), _password.text);
      if (mounted) widget.onSignedIn(auth);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'PHONE_NOT_VERIFIED') {
        await _verifyPhone(auth);
      } else {
        setState(() => _error = authErrorText(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The account exists but its phone was never verified, so send a code and ask for it.
  Future<void> _verifyPhone(AuthService auth) async {
    final phone = _phone.text.trim();
    try {
      await auth.resendOtp(phone);
    } on ApiException catch (e) {
      // A code sent moments ago still works, so only other failures stop here.
      if (e.code != 'OTP_COOLDOWN') {
        if (mounted) setState(() => _error = authErrorText(e));
        return;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerifyPhoneScreen(auth: auth, phone: phone, onSignedIn: widget.onSignedIn),
      ),
    );
  }

  Future<void> _forgotPassword() async {
    final auth = _createAuth();
    if (auth == null) return;
    setState(() => _error = null);
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ForgotPasswordScreen(auth: auth, initialPhone: _phone.text.trim())),
    );
    if (changed == true && mounted) {
      _password.clear();
      showSnack(context, 'Password changed. Sign in with your new password.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPage(
      title: 'Sign in',
      subtitle: 'Book your seat, bid fairly, travel safely.',
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Mobile number', hintText: '0771234567'),
                validator: validatePhone,
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _password,
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
            ]),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _forgotPassword, child: const Text('Forgot password?')),
        ),
        const SizedBox(height: 8),
        AuthError(_error),
        BusyButton(busy: _busy, onPressed: _submit, label: 'Sign in'),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => _open((auth) => RegisterScreen(auth: auth, onSignedIn: widget.onSignedIn)),
          child: const Text('Create an account'),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Developer settings'),
          children: [
            TextField(
              controller: _baseUrl,
              decoration: const InputDecoration(
                labelText: 'API base URL',
                helperText: 'Android emulator: 10.0.2.2 · iOS simulator: localhost · phone: your computer\'s Wi-Fi IP',
                helperMaxLines: 2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
