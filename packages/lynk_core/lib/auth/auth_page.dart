import 'package:flutter/material.dart';
import '../src/widgets/primary_button.dart';
import 'widgets/custom_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Phone number + OTP is the only way in — no password, no email, no OAuth.
/// A single `signInWithOtp(phone: ...)` call covers both new and returning
/// users (`shouldCreateUser: true`), so there's no separate login/signup mode
/// to toggle between; the code-verification step is the only second screen.
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  String? _pendingPhone;

  void _onCodeSent(String phone) {
    setState(() => _pendingPhone = phone);
  }

  void _onBackToPhone() {
    setState(() => _pendingPhone = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 40.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/images/lynk-x_combined-logo.png',
                      package: 'lynk_core',
                      width: 220,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _pendingPhone == null ? 'Welcome' : 'Enter your code',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _pendingPhone == null
                        ? 'Enter your phone number to sign in or create an account.'
                        : 'We sent a code to $_pendingPhone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_pendingPhone == null)
                    _PhoneForm(onCodeSent: _onCodeSent)
                  else
                    _OtpForm(phone: _pendingPhone!, onBack: _onBackToPhone),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneForm extends StatefulWidget {
  final ValueChanged<String> onCodeSent;
  const _PhoneForm({required this.onCodeSent});

  @override
  State<_PhoneForm> createState() => _PhoneFormState();
}

class _PhoneFormState extends State<_PhoneForm> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your phone number')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: phone,
        channel: OtpChannel.sms,
      );
      if (mounted) widget.onCodeSent(phone);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomTextField(
          hintText: 'Phone Number (e.g. +254...)',
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          suffixIcon: Icon(
            Icons.phone_android_outlined,
            color: Colors.grey[600],
            size: 20,
          ),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          text: 'Send Code',
          onPressed: _sendCode,
          isLoading: _isLoading,
        ),
      ],
    );
  }
}

class _OtpForm extends StatefulWidget {
  final String phone;
  final VoidCallback onBack;
  const _OtpForm({required this.phone, required this.onBack});

  @override
  State<_OtpForm> createState() => _OtpFormState();
}

class _OtpFormState extends State<_OtpForm> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the code we sent you')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.verifyOTP(
        phone: widget.phone,
        token: code,
        type: OtpType.sms,
      );
      // Successful verification updates the auth session; app.dart's
      // onAuthStateChange listener (signedIn) takes over from here — no
      // explicit navigation needed, the router redirect will pick it up.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _isResending = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: widget.phone,
        channel: OtpChannel.sms,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code resent')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomTextField(
          hintText: '6-digit code',
          controller: _codeController,
          keyboardType: TextInputType.number,
          suffixIcon: Icon(
            Icons.password_outlined,
            color: Colors.grey[600],
            size: 20,
          ),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          text: 'Verify',
          onPressed: _verify,
          isLoading: _isLoading,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: widget.onBack,
              child: const Text(
                'Change number',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
            TextButton(
              onPressed: _isResending ? null : _resend,
              child: Text(
                _isResending ? 'Resending…' : 'Resend code',
                style: const TextStyle(
                  color: Color(0xFF00FF00),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
