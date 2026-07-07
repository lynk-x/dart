import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:lynk_core/core.dart';
import 'package:lynk_x/services/push_notification_service.dart';
import '../models/country.dart';

enum SetupStep { identity, notifications }

class ProfileSetupScreen extends StatefulWidget {
  final String? next;

  const ProfileSetupScreen({super.key, this.next});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKeyIdentity = GlobalKey<FormState>();

  SetupStep _currentStep = SetupStep.identity;

  // Identity Fields
  final _fullNameController = TextEditingController();
  final _userNameController = TextEditingController();
  String? _selectedCountryCode = '';
  XFile? _imageFile;
  Uint8List? _imageBytes;

  // Username validation state
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  Timer? _debounceTimer;

  /// Monotonic request id; in-flight RPCs check this against the latest
  /// before applying their result, so a slow earlier response cannot
  /// clobber a faster later one.
  int _usernameRequestId = 0;

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
    super.dispose();
  }

  void _onUsernameChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    
    final name = _userNameController.text.trim();
    if (name.length < 3) {
      if (mounted) { setState(() => _isUsernameAvailable = null); }
      return;
    }

    final requestId = ++_usernameRequestId;
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _isCheckingUsername = true);
      try {
        final response = await sb.Supabase.instance.client.schema('api').rpc(
          'is_username_available',
          params: {'username_to_check': name},
        );
        // Discard stale responses: a faster later request may have already
        // landed and updated the UI.
        if (!mounted || requestId != _usernameRequestId) return;
        setState(() {
          _isUsernameAvailable = response as bool;
          _isCheckingUsername = false;
        });
      } catch (e) {
        if (!mounted || requestId != _usernameRequestId) return;
        setState(() => _isCheckingUsername = false);
      }
    });
  }


  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      if (mounted) setState(() { _imageFile = pickedFile; _imageBytes = bytes; });
    }
  }

  void _goToNextFromIdentity() {
    if (!_formKeyIdentity.currentState!.validate()) return;
    _saveIdentityAndGoToNotifications();
  }

  Future<void> _saveIdentityAndGoToNotifications() async {
    setState(() => _isSubmitting = true);
    try {
      final cubit = context.read<ProfileCubit>();
      if (_imageFile != null) await cubit.uploadAvatar(_imageFile!);
      await cubit.updateProfile(
        fullName: _fullNameController.text.trim(),
        userName: _userNameController.text.trim(),
        countryCode: _selectedCountryCode,
      );
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _currentStep = SetupStep.notifications;
        });
      }
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
    if (mounted) context.go(widget.next ?? '/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildStepIndicator(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: _buildCurrentStepView(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    const labels = ['Profile', 'Notifications'];
    final currentIndex = _currentStep == SetupStep.notifications ? 1 : 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: List.generate(labels.length * 2 - 1, (i) {
          if (i.isOdd) return const SizedBox(width: 8);
          final stepIndex = i ~/ 2;
          final isActive = stepIndex == currentIndex;
          final isComplete = stepIndex < currentIndex;
          return Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 3,
                  decoration: BoxDecoration(
                    color: (isActive || isComplete) ? context.accentColor : Colors.white12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[stepIndex],
                  style: TextStyle(
                    fontSize: 10,
                    color: isActive ? Colors.white70 : Colors.white24,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case SetupStep.identity:
        return _buildIdentityStep();
      case SetupStep.notifications:
        return _buildNotificationsStep();
    }
  }

  void _showCountryPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.tertiary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Select Country', 
              style: AppTypography.interTight(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: kSupportedCountries.length,
                itemBuilder: (context, index) {
                  final country = kSupportedCountries[index];
                  final isSelected = _selectedCountryCode == country.code;
                  return ListTile(
                    title: Text(country.name, style: const TextStyle(color: Colors.white)),
                    trailing: isSelected ? Icon(Icons.check_circle, color: context.accentColor) : null,
                    onTap: () {
                      setState(() => _selectedCountryCode = country.code);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountrySelector() {
    final country = _selectedCountryCode != null 
        ? kSupportedCountries.firstWhere((c) => c.code == _selectedCountryCode, orElse: () => const Country(name: 'Global', code: 'GL'))
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('Country', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        InkWell(
          onTap: () => _showCountryPicker(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                if (country != null) ...[
                  Text(country.name, style: const TextStyle(color: Colors.white, fontSize: 16)),
                ] else ...[
                  const Text('Select Country', style: TextStyle(color: Colors.white54, fontSize: 16)),
                ],
                const Spacer(),
                const Icon(Icons.arrow_drop_down, color: Colors.white54),
              ],
            ),
          ),
        ),
      ],
    );
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
              helperText: _userNameController.text.isNotEmpty && _userNameController.text.trim().length < 3
                  ? 'Username must be at least 3 characters'
                  : null,
              suffixIcon: _isCheckingUsername
                ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)))
                : (_isUsernameAvailable == true
                    ? Icon(Icons.check_circle, color: context.accentColor, size: 20)
                    : (_isUsernameAvailable == false 
                        ? const Icon(Icons.error, color: Colors.redAccent, size: 20)
                        : null)),
              validator: (v) => v == null || v.isEmpty ? 'Required' : (_isUsernameAvailable == false ? 'Username already taken' : null),
            ).animate().slideX(begin: -0.1).fadeIn(delay: 200.ms),
            const SizedBox(height: 24),
            _buildCountrySelector().animate().slideX(begin: -0.1).fadeIn(delay: 300.ms),
            const SizedBox(height: 60),
            _isSubmitting
                ? Center(child: CircularProgressIndicator(color: context.accentColor))
                : PrimaryButton(
                    text: 'Continue',
                    onPressed: (_isCheckingUsername || _isUsernameAvailable == false)
                        ? null
                        : _goToNextFromIdentity,
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
          Icon(Icons.notifications_active_outlined, size: 80, color: context.accentColor).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 40),
          const Text(
            'Stay in the loop',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 16),
          const Text(
            'Get live event updates, forum mentions, and ticket alerts the moment they happen.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.white54, height: 1.5),
          ).animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 60),
          PrimaryButton(text: 'Enable Notifications', onPressed: _finishSetup),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _finishSetup,
            child: const Text('Skip for now', style: TextStyle(color: Colors.white38)),
          ),
          const SizedBox(height: 4),
          const Text(
            'You can turn these on later in your device settings.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.white24),
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
                border: Border.all(color: context.accentColor.withValues(alpha: 0.3), width: 1.5),
                image: _imageBytes != null ? DecorationImage(image: MemoryImage(_imageBytes!), fit: BoxFit.cover) : null,
              ),
              child: _imageFile == null ? const Icon(Icons.person, size: 60, color: Colors.white24) : null,
            ),
            Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: context.accentColor, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, size: 20, color: Colors.black))),
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
    String? helperText,
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
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: context.accentColor, width: 1)),
            suffixIcon: suffixIcon,
            helperText: helperText,
            helperStyle: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }
}
