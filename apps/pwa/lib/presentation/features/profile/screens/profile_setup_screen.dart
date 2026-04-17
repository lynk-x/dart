import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:lynk_core/core.dart';
import 'package:lynk_x/services/push_notification_service.dart';

enum SetupStep { identity, security, notifications }

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKeyIdentity = GlobalKey<FormState>();
  final _formKeySecurity = GlobalKey<FormState>();
  
  SetupStep _currentStep = SetupStep.identity;

  // Identity Fields
  final _fullNameController = TextEditingController();
  final _userNameController = TextEditingController();
  File? _imageFile;

  // Username validation state
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  Timer? _debounceTimer;

  // Security Fields
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _userNameController.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _userNameController.removeListener(_onUsernameChanged);
    _debounceTimer?.cancel();
    _fullNameController.dispose();
    _userNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    
    final name = _userNameController.text.trim();
    if (name.length < 3) {
      if (mounted) setState(() => _isUsernameAvailable = null);
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _isCheckingUsername = true);
      try {
        final response = await sb.Supabase.instance.client.rpc(
          'is_username_available',
          params: {'username_to_check': name},
        );
        if (mounted) {
          setState(() {
            _isUsernameAvailable = response as bool;
            _isCheckingUsername = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isCheckingUsername = false);
      }
    });
  }


  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) setState(() => _imageFile = File(pickedFile.path));
  }

  void _goToSecurity() {
    if (!_formKeyIdentity.currentState!.validate()) return;
    setState(() => _currentStep = SetupStep.security);
  }

  void _goToNotifications() async {
    if (!_formKeySecurity.currentState!.validate()) return;
    
    setState(() => _isSubmitting = true);
    try {
      final cubit = context.read<ProfileCubit>();
      
      // 1. Save Identity
      if (_imageFile != null) await cubit.uploadAvatar(_imageFile!);
      await cubit.updateProfile(
        fullName: _fullNameController.text.trim(),
        userName: _userNameController.text.trim(),
      );

      // 2. Set Password (for Ghost accounts)
      await sb.Supabase.instance.client.auth.updateUser(
        sb.UserAttributes(password: _passwordController.text.trim()),
      );

      setState(() {
        _isSubmitting = false;
        _currentStep = SetupStep.notifications;
      });
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _finishSetup() async {
    // Request push notification permission now that the user has opted in
    await PushNotificationService.instance.init();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: _buildCurrentStepView(),
        ),
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case SetupStep.identity:
        return _buildIdentityStep();
      case SetupStep.security:
        return _buildSecurityStep();
      case SetupStep.notifications:
        return _buildNotificationsStep();
    }
  }

  Widget _buildIdentityStep() {
    return SingleChildScrollView(
      key: const ValueKey('identity'),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
      child: Form(
        key: _formKeyIdentity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader('Build your profile', 'Tell us a bit about yourself to join the Lynk-X community.'),
            const SizedBox(height: 48),
            _buildAvatarPicker(),
            const SizedBox(height: 48),
            _buildTextField(
              controller: _fullNameController,
              label: 'Full Name',
              hint: 'John Doe',
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ).animate().slideX(begin: -0.1).fadeIn(delay: 100.ms),
            const SizedBox(height: 24),
            _buildTextField(
              controller: _userNameController,
              label: 'Username',
              hint: 'johndoe_99',
              suffixIcon: _isCheckingUsername 
                ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)))
                : (_isUsernameAvailable == true 
                    ? const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
                    : (_isUsernameAvailable == false 
                        ? const Icon(Icons.error, color: Colors.redAccent, size: 20)
                        : null)),
              validator: (v) => v == null || v.isEmpty ? 'Required' : (_isUsernameAvailable == false ? 'Username already taken' : null),
            ).animate().slideX(begin: -0.1).fadeIn(delay: 200.ms),
            const SizedBox(height: 60),
            PrimaryButton(
              text: 'Next: Security', 
              onPressed: (_isCheckingUsername || _isUsernameAvailable == false) ? null : _goToSecurity
            ),
          ],
        ),
      ),
    );
  }

  // --- SECURITY STEP ---
  Widget _buildSecurityStep() {
    return SingleChildScrollView(
      key: const ValueKey('security'),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
      child: Form(
        key: _formKeySecurity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader('Secure your account', 'Set a strong password to access your tickets and forums anywhere.'),
            const SizedBox(height: 60),
            _buildTextField(
              controller: _passwordController,
              label: 'Password',
              hint: '••••••••',
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white24),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (v) => v == null || v.length < 8 ? 'Min 8 characters' : null,
            ).animate().slideX(begin: -0.1).fadeIn(),
            const SizedBox(height: 24),
            _buildTextField(
              controller: _confirmPasswordController,
              label: 'Confirm Password',
              hint: '••••••••',
              obscureText: _obscurePassword,
              validator: (v) => v != _passwordController.text ? 'Passwords do not match' : null,
            ).animate().slideX(begin: -0.1).fadeIn(delay: 100.ms),
            const SizedBox(height: 60),
            _isSubmitting 
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : PrimaryButton(text: 'Create Account Password', onPressed: _goToNotifications),
            TextButton(
              onPressed: () => setState(() => _currentStep = SetupStep.identity),
              child: const Text('Go Back', style: TextStyle(color: Colors.white30)),
            ),
          ],
        ),
      ),
    );
  }

  // --- NOTIFICATIONS STEP ---
  Widget _buildNotificationsStep() {
    return Padding(
      key: const ValueKey('notifications'),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.notifications_active_outlined, size: 80, color: AppColors.primary).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 40),
          const Text(
            'Keep Up with the Community',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 16),
          const Text(
            'Notifications are essential to get live event updates, forum mentions, and ticket alerts. We promise not to spam.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.white54, height: 1.5),
          ).animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 60),
          PrimaryButton(text: 'Enable Notifications', onPressed: _finishSetup),
          TextButton(
            onPressed: _finishSetup,
            child: const Text('I\'ll do this later', style: TextStyle(color: Colors.white24)),
          ),
        ],
      ),
    );
  }

  // --- HELPERS ---
  Widget _buildHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(subtitle, style: TextStyle(color: Colors.white54, fontSize: 16)),
      ],
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Widget _buildAvatarPicker() {
    return Center(
      child: GestureDetector(
        onTap: _pickImage,
        child: Stack(
          children: [
            Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: Colors.white10,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
                image: _imageFile != null ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover) : null,
              ),
              child: _imageFile == null ? const Icon(Icons.person, size: 60, color: Colors.white24) : null,
            ),
            Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, size: 20, color: Colors.black))),
          ],
        ),
      ).animate().scale(curve: Curves.easeOutBack),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 12),
        TextFormField(
          controller: controller, validator: validator, obscureText: obscureText,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint, hintStyle: const TextStyle(color: Colors.white10),
            filled: true, fillColor: Colors.white.withValues(alpha: 0.04),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 1)),
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}
