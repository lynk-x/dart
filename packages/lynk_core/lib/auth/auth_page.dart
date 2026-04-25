import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../src/widgets/primary_button.dart';
import 'widgets/social_button.dart';
import 'widgets/custom_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isLogin = true;
  bool _useEmail = false;

  Future<void> _signInWithProvider(BuildContext context, OAuthProvider provider) async {
    try {
      // Web uses the current origin as the redirect; native uses the deep-link scheme.
      final redirectTo = kIsWeb ? null : 'io.supabase.lynkx://login-callback/';
      await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: redirectTo,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  Center(
                    child: Image.asset(
                      'assets/images/lynk-x_combined-logo.png',
                      package: 'lynk_core',
                      width: 220,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Title & Subtitle
                  Text(
                    _isLogin ? 'Welcome Back' : 'Create Account',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isLogin
                        ? 'Fill out the information below in order to access your account.'
                        : "Let's get started by filling out the form below.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Toggle
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => _useEmail = !_useEmail),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _useEmail ? 'Use Phone Number instead' : 'Use Email instead',
                        style: const TextStyle(
                          color: Color(0xFF00FF00),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Form
                  if (_isLogin)
                    _LoginForm(useEmail: _useEmail)
                  else
                    _SignUpForm(useEmail: _useEmail),

                  const SizedBox(height: 32),
                  const _OrDivider(),
                  const SizedBox(height: 32),

                  // Social Buttons
                  SocialButton(
                    text: 'Continue with Google',
                    icon: Icons.g_mobiledata,
                    onPressed: () => _signInWithProvider(context, OAuthProvider.google),
                  ),
                  const SizedBox(height: 16),
                  SocialButton(
                    text: 'Continue with Apple',
                    icon: Icons.apple,
                    onPressed: () => _signInWithProvider(context, OAuthProvider.apple),
                  ),

                  if (_isLogin) ...[
                    const SizedBox(height: 32),
                    Center(
                      child: TextButton(
                        onPressed: () => context.go('/forgot-password'),
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: Color(0xFF00FF00),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Footer
                  const SizedBox(height: 60),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _FooterLink(
                        text: 'Create Account',
                        isActive: !_isLogin,
                        onPressed: () => setState(() => _isLogin = false),
                      ),
                      _FooterLink(
                        text: 'Log In',
                        isActive: _isLogin,
                        onPressed: () => setState(() => _isLogin = true),
                      ),
                    ],
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

class _FooterLink extends StatelessWidget {
  final String text;
  final bool isActive;
  final VoidCallback onPressed;

  const _FooterLink({
    required this.text,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: (isActive ? const Color(0xFF00FF00) : Colors.white)
              .withValues(alpha: isActive ? 1.0 : 0.5),
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LoginForm extends StatefulWidget {
  final bool useEmail;
  const _LoginForm({required this.useEmail});

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _signIn() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text.trim();

    if (identifier.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter your ${widget.useEmail ? "email" : "phone number"} and password')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (widget.useEmail) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: identifier,
          password: password,
        );
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          phone: identifier,
          password: password,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
          ),
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
          hintText: widget.useEmail ? 'Email Address' : 'Phone Number (e.g. +254...)',
          controller: _identifierController,
          keyboardType: widget.useEmail ? TextInputType.emailAddress : TextInputType.phone,
          suffixIcon: Icon(
            widget.useEmail ? Icons.email_outlined : Icons.phone_android_outlined,
            color: Colors.grey[600],
            size: 20,
          ),
        ),
        const SizedBox(height: 16),
        CustomTextField(
          hintText: 'Password',
          controller: _passwordController,
          isPassword: true,
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          text: 'Sign In',
          onPressed: _signIn,
          isLoading: _isLoading,
        ),
      ],
    );
  }
}

class _SignUpForm extends StatefulWidget {
  final bool useEmail;
  const _SignUpForm({required this.useEmail});

  @override
  State<_SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<_SignUpForm> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;

  Future<void> _signUp() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text.trim();
    if (password != _confirmController.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (widget.useEmail) {
        await Supabase.instance.client.auth.signUp(
          email: identifier,
          password: password,
        );
        if (mounted) {
          context.go('/verify-email?email=${Uri.encodeComponent(identifier)}');
        }
      } else {
        await Supabase.instance.client.auth.signUp(
          phone: identifier,
          password: password,
        );
        // For phone sign up, we might need a different verification screen or OTP
        // For now, assuming standard flow
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
          ),
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
          hintText: widget.useEmail ? 'Email Address' : 'Phone Number (e.g. +254...)',
          controller: _identifierController,
          keyboardType: widget.useEmail ? TextInputType.emailAddress : TextInputType.phone,
          suffixIcon: Icon(
            widget.useEmail ? Icons.email_outlined : Icons.phone_android_outlined,
            color: Colors.grey[600],
            size: 20,
          ),
        ),
        const SizedBox(height: 16),
        CustomTextField(
          hintText: 'Password',
          controller: _passwordController,
          isPassword: true,
        ),
        const SizedBox(height: 16),
        CustomTextField(
          hintText: 'Confirm Password',
          controller: _confirmController,
          isPassword: true,
        ),
        const SizedBox(height: 32),
        PrimaryButton(
          text: 'Get Started',
          onPressed: _signUp,
          isLoading: _isLoading,
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Or sign in with',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
        ),
      ),
    );
  }
}

