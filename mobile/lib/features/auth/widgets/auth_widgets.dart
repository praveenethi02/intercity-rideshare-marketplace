import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/api_client.dart';

// Colours from the Figma design system.
const _brand900 = Color(0xFF0B203F);
const _brand500 = Color(0xFF1257D9);

/// Seconds the backend makes a user wait between codes.
const otpCooldownSeconds = 60;

/// Same rule as normalizePhone in the backend.
String? validatePhone(String? value) {
  final phone = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^(\+94|94|0)7\d{8}$').hasMatch(phone) ? null : 'Enter a valid mobile number, like 0771234567';
}

/// Same rule as newPassword in the backend.
String? validateNewPassword(String? value) {
  final password = value ?? '';
  if (password.length < 8) return 'Use at least 8 characters';
  if (utf8.encode(password).length > 72) return 'Use a shorter password';
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(password) || !RegExp(r'\d').hasMatch(password)) {
    return 'Use at least one letter and one number';
  }
  return null;
}

String? validateOtp(String? value) =>
    RegExp(r'^\d{6}$').hasMatch((value ?? '').trim()) ? null : 'Enter the 6-digit code';

/// The message to show for a failed request.
String authErrorText(Object error) {
  if (error is ApiException && error.fieldErrors.isNotEmpty) {
    return error.fieldErrors.map((e) => e.message).join('\n');
  }
  return error is ApiException ? error.message : '$error';
}

/// Page layout shared by every sign-in screen.
class AuthPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  const AuthPage({super.key, required this.title, required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: _brand500).copyWith(primary: _brand500),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: Navigator.canPop(context) ? AppBar(backgroundColor: Colors.white, elevation: 0) : null,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    title,
                    style: base.textTheme.headlineSmall?.copyWith(color: _brand900, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: base.textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Error message under a form. Draws nothing when there is no error.
class AuthError extends StatelessWidget {
  final String? message;
  const AuthError(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        liveRegion: true,
        child: Text(text, style: TextStyle(color: colors.error)),
      ),
    );
  }
}

/// Password field with a show or hide button.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?) validator;
  final ValueChanged<String>? onSubmitted;
  final List<String> autofillHints;
  const PasswordField({
    super.key,
    required this.controller,
    required this.validator,
    this.label = 'Password',
    this.onSubmitted,
    this.autofillHints = const [AutofillHints.password],
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _hidden,
      autofillHints: widget.autofillHints,
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          tooltip: _hidden ? 'Show password' : 'Hide password',
          icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}

/// Asks for a new code, then counts down until another one is allowed.
class ResendCodeButton extends StatefulWidget {
  final Future<void> Function() onResend;
  final ValueChanged<String?> onResult;
  const ResendCodeButton({super.key, required this.onResend, required this.onResult});

  @override
  State<ResendCodeButton> createState() => _ResendCodeButtonState();
}

class _ResendCodeButtonState extends State<ResendCodeButton> {
  Timer? _timer;
  int _seconds = otpCooldownSeconds;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _seconds = otpCooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _seconds -= 1);
      if (_seconds <= 0) timer.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      await widget.onResend();
      if (!mounted) return;
      _startCountdown();
      widget.onResult(null);
    } catch (e) {
      if (mounted) widget.onResult(authErrorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _seconds > 0;
    return TextButton(
      onPressed: waiting || _sending ? null : _resend,
      child: Text(waiting ? 'Send a new code in ${_seconds}s' : 'Send a new code'),
    );
  }
}
