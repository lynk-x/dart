import 'dart:async';
import 'package:flutter/material.dart';
import '../src/widgets/primary_button.dart';
import 'widgets/custom_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../src/utils/friendly_error.dart';

enum _LoginMode { email, phone }

/// Email + OTP is the primary way in, with phone + OTP as an alternative for
/// users who'd rather not share an email — no password, no OAuth. A single
/// `signInWithOtp(...)` call covers both new and returning users
/// (`shouldCreateUser: true`), so there's no separate login/signup mode to
/// toggle between; the code-verification step is the only second screen,
/// for either identifier.
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  _LoginMode _mode = _LoginMode.email;
  String? _pendingPhone;
  String? _pendingEmail;

  void _onCodeSent(String identifier) {
    setState(() {
      if (_mode == _LoginMode.phone) {
        _pendingPhone = identifier;
      } else {
        _pendingEmail = identifier;
      }
    });
  }

  void _onBack() {
    setState(() {
      _pendingPhone = null;
      _pendingEmail = null;
    });
  }

  void _switchMode(_LoginMode mode) {
    setState(() {
      _mode = mode;
      _pendingPhone = null;
      _pendingEmail = null;
    });
  }

  bool get _isPending => _pendingPhone != null || _pendingEmail != null;

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
                    !_isPending ? 'Already Have The Tickets?' : 'Welcome back',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _pendingPhone != null
                        ? 'We sent a code to $_pendingPhone.'
                        : _pendingEmail != null
                            ? 'We sent a code to $_pendingEmail.'
                            : _mode == _LoginMode.phone
                                ? 'Enter the phone number you use for checkout for an OTP'
                                : 'Enter the email you use for checkout for an OTP',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!_isPending) ...[
                    _ModeToggle(mode: _mode, onChanged: _switchMode),
                    const SizedBox(height: 16),
                    _mode == _LoginMode.phone
                        ? _PhoneForm(onCodeSent: _onCodeSent)
                        : _EmailForm(onCodeSent: _onCodeSent),
                  ] else if (_pendingPhone != null)
                    _OtpForm(
                      identifier: _pendingPhone!,
                      type: OtpType.sms,
                      onBack: _onBack,
                    )
                  else
                    _OtpForm(
                      identifier: _pendingEmail!,
                      type: OtpType.email,
                      onBack: _onBack,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final _LoginMode mode;
  final ValueChanged<_LoginMode> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: _buildTab(context, 'Email', _LoginMode.email)),
          Expanded(child: _buildTab(context, 'Phone', _LoginMode.phone)),
        ],
      ),
    );
  }

  Widget _buildTab(BuildContext context, String label, _LoginMode tabMode) {
    final isSelected = mode == tabMode;
    return GestureDetector(
      onTap: () => onChanged(tabMode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.w600,
            fontSize: 14,
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

class _DialCodeCountry {
  final String code;
  final String displayName;
  final String phonePrefix;
  final int? phoneDigits;
  const _DialCodeCountry({
    required this.code,
    required this.displayName,
    required this.phonePrefix,
    this.phoneDigits,
  });
}

class _PhoneFormState extends State<_PhoneForm> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  bool _isLoadingCountries = true;

  List<_DialCodeCountry> _countries = const [];
  _DialCodeCountry _selectedCountry = const _DialCodeCountry(
    code: 'KE', displayName: 'Kenya', phonePrefix: '+254', phoneDigits: 9,
  );

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  // Backed by api.v1_countries' phone_prefix/phone_digits columns — the same
  // source checkout's CountryPhoneSelect uses, so both sides normalize a
  // phone number to the identical E.164 shape.
  Future<void> _loadCountries() async {
    try {
      final data = await Supabase.instance.client
          .schema('api')
          .from('v1_countries')
          .select('code, display_name, phone_prefix, phone_digits')
          .eq('is_active', true)
          .not('phone_prefix', 'is', null)
          .order('display_name');

      final countries = (data as List)
          .map((row) => _DialCodeCountry(
                code: row['code'] as String,
                displayName: row['display_name'] as String,
                phonePrefix: row['phone_prefix'] as String,
                phoneDigits: row['phone_digits'] as int?,
              ))
          .toList();

      if (!mounted) return;
      setState(() {
        _countries = countries;
        final match = countries.where((c) => c.code == _selectedCountry.code);
        if (match.isNotEmpty) _selectedCountry = match.first;
        _isLoadingCountries = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingCountries = false);
    }
  }

  /// Normalizes the national-format input against the selected country's
  /// dial code, mirroring web's normalizeToE164 in web/src/utils/phone.ts —
  /// keeping login and checkout's contact phone on the same E.164 shape is
  /// what lets a returning guest's tickets actually be found by phone.
  String? _normalizeToE164(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    final dialDigits = _selectedCountry.phonePrefix.replaceAll(RegExp(r'\D'), '');

    if (cleaned.startsWith('+')) cleaned = cleaned.substring(1);
    if (cleaned.startsWith(dialDigits)) {
      cleaned = cleaned.substring(dialDigits.length);
    } else if (cleaned.startsWith('0')) {
      cleaned = cleaned.substring(1);
    }

    if (!RegExp(r'^\d+$').hasMatch(cleaned)) return null;
    final expected = _selectedCountry.phoneDigits;
    if (expected != null && cleaned.length != expected) return null;
    if (expected == null && (cleaned.length < 6 || cleaned.length > 14)) return null;

    return '+$dialDigits$cleaned';
  }

  Future<void> _sendCode() async {
    final raw = _phoneController.text.trim();
    final phone = raw.isEmpty ? null : _normalizeToE164(raw);
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid phone number')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: phone,
        channel: OtpChannel.sms,
        // Tags a first-time signup so internal.handle_new_user() knows to
        // auto-provision an attendee profile+account atomically. Ignored by
        // GoTrue for an existing user (login, not signup) — safe to always send.
        data: const {'account_type': 'attendee'},
      );
      if (mounted) widget.onCodeSent(phone);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toFriendlyMessage()), backgroundColor: Colors.red),
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
        Container(
          height: 48,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: _isLoadingCountries
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCountry.code,
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.black54),
                    style: const TextStyle(color: Colors.black, fontSize: 15),
                    items: _countries
                        .map((c) => DropdownMenuItem(
                              value: c.code,
                              child: Text('${c.displayName} (${c.phonePrefix})'),
                            ))
                        .toList(),
                    onChanged: (code) {
                      final match = _countries.where((c) => c.code == code);
                      if (match.isNotEmpty) {
                        setState(() => _selectedCountry = match.first);
                      }
                    },
                  ),
                ),
        ),
        const SizedBox(height: 12),
        CustomTextField(
          hintText: 'Phone Number',
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

class _EmailForm extends StatefulWidget {
  final ValueChanged<String> onCodeSent;
  const _EmailForm({required this.onCodeSent});

  @override
  State<_EmailForm> createState() => _EmailFormState();
}

class _EmailFormState extends State<_EmailForm> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _sendCode() async {
    final email = _emailController.text.trim().toLowerCase();
    if (!_emailPattern.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        // Tags a first-time signup so internal.handle_new_user() knows to
        // auto-provision an attendee profile+account atomically. Ignored by
        // GoTrue for an existing user (login, not signup) — safe to always send.
        data: const {'account_type': 'attendee'},
      );
      if (mounted) widget.onCodeSent(email);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toFriendlyMessage()), backgroundColor: Colors.red),
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
          hintText: 'Email address',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          suffixIcon: Icon(
            Icons.email_outlined,
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

/// Verifies the code sent to either a phone number or an email address —
/// [type] selects which, and [identifier] is passed as the matching
/// `phone`/`email` param to both `verifyOTP` and the resend `signInWithOtp`.
class _OtpForm extends StatefulWidget {
  final String identifier;
  final OtpType type;
  final VoidCallback onBack;
  const _OtpForm({required this.identifier, required this.type, required this.onBack});

  @override
  State<_OtpForm> createState() => _OtpFormState();
}

class _OtpFormState extends State<_OtpForm> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  bool _hasFailed = false;

  int _resendCooldown = 30;
  Timer? _cooldownTimer;

  bool get _isPhone => widget.type == OtpType.sms;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _resendCooldown = 30;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendCooldown--);
      if (_resendCooldown <= 0) timer.cancel();
    });
  }

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
        phone: _isPhone ? widget.identifier : null,
        email: _isPhone ? null : widget.identifier,
        token: code,
        type: widget.type,
      );
      // Successful verification updates the auth session; app.dart's
      // onAuthStateChange listener (signedIn) takes over from here — no
      // explicit navigation needed, the router redirect will pick it up.
    } catch (e) {
      if (mounted) {
        setState(() => _hasFailed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toFriendlyMessage()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reportIssue() async {
    final message = await showDialog<String>(
      context: context,
      builder: (context) => _ReportLoginIssueDialog(identifier: widget.identifier),
    );
    if (message == null || !mounted) return;

    try {
      await Supabase.instance.client.schema('api').from('v1_support_tickets').insert({
        'email': _isPhone ? null : widget.identifier,
        'phone': _isPhone ? widget.identifier : null,
        'subject': 'Failed login (${_isPhone ? 'phone' : 'email'} OTP)',
        'message': message.trim().isEmpty
            ? 'User could not verify their OTP code.'
            : message.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks — our team will look into this.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toFriendlyMessage()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _resend() async {
    setState(() => _isResending = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: _isPhone ? widget.identifier : null,
        email: _isPhone ? null : widget.identifier,
        channel: OtpChannel.sms, // ignored by the SDK when email is set
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code resent')),
        );
        _startCooldown();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toFriendlyMessage()), backgroundColor: Colors.red),
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
              child: Text(
                _isPhone ? 'Change number' : 'Change email',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
            TextButton(
              onPressed: (_isResending || _resendCooldown > 0) ? null : _resend,
              child: Text(
                _isResending
                    ? 'Resending…'
                    : (_resendCooldown > 0 ? 'Resend code (${_resendCooldown}s)' : 'Resend code'),
                style: TextStyle(
                  color: (_resendCooldown > 0 && !_isResending)
                      ? Colors.white38
                      : const Color(0xFF00FF00),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        if (_hasFailed) ...[
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: _reportIssue,
              child: const Text(
                'Trouble logging in? Report an issue',
                style: TextStyle(color: Colors.white54, fontSize: 13, decoration: TextDecoration.underline),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Collects an optional message before submitting a login-failure report —
/// the phone/email is already known (widget.identifier) and sent silently,
/// so the user only ever types what went wrong, if anything.
class _ReportLoginIssueDialog extends StatefulWidget {
  final String identifier;
  const _ReportLoginIssueDialog({required this.identifier});

  @override
  State<_ReportLoginIssueDialog> createState() => _ReportLoginIssueDialogState();
}

class _ReportLoginIssueDialogState extends State<_ReportLoginIssueDialog> {
  final _messageController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Report a Login Issue', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'We\'ll include ${widget.identifier} so our team can look into your account.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _messageController,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'What happened? (optional)',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _messageController.text),
          child: const Text('Submit', style: TextStyle(color: Color(0xFF00FF00))),
        ),
      ],
    );
  }
}
