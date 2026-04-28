import 'dart:async';
import 'package:flutter/material.dart' hide TextField;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/shared/widgets/text_field.dart';
import 'package:country_flags/country_flags.dart';

class Country {
  final String name;
  final String code;
  const Country({required this.name, required this.code});
}

const List<Country> kSupportedCountries = [
  Country(name: 'Kenya', code: 'KE'),
  Country(name: 'Uganda', code: 'UG'),
  Country(name: 'Tanzania', code: 'TZ'),
  Country(name: 'Rwanda', code: 'RW'),
  Country(name: 'Nigeria', code: 'NG'),
  Country(name: 'South Africa', code: 'ZA'),
  Country(name: 'United States', code: 'US'),
  Country(name: 'United Kingdom', code: 'GB'),
  Country(name: 'Global', code: 'GL'),
];

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _taglineController = TextEditingController();

  bool _initialized = false;
  String _initialUsername = '';
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  Timer? _debounceTimer;
  bool _isOpeningGallery = false;
  bool _uploadingAvatar = false;
  String? _selectedCountryCode;

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_onUsernameChanged);
    _usernameController.addListener(_onFieldChanged);
    _nameController.addListener(_onFieldChanged);
    _bioController.addListener(_onFieldChanged);
    _taglineController.addListener(_onFieldChanged);
    
    // Load profile data on entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProfileCubit>().loadProfile();
    });
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _usernameController.removeListener(_onUsernameChanged);
    _usernameController.removeListener(_onFieldChanged);
    _nameController.removeListener(_onFieldChanged);
    _bioController.removeListener(_onFieldChanged);
    _taglineController.removeListener(_onFieldChanged);
    _debounceTimer?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _taglineController.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    final name = _usernameController.text.trim();
    if (name.toLowerCase() == _initialUsername.toLowerCase() || name.length < 3) {
      if (mounted) setState(() { _isUsernameAvailable = null; _isCheckingUsername = false; });
      return;
    }
    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    setState(() => _isCheckingUsername = true);
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
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
      } catch (_) {
        if (mounted) setState(() => _isCheckingUsername = false);
      }
    });
  }

  Future<void> _pickImage(BuildContext context) async {
    setState(() => _isOpeningGallery = true);
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 500,
      );

      if (image != null && context.mounted) {
        setState(() => _uploadingAvatar = true);
        context.read<ProfileCubit>().uploadAvatar(image);
      }
    } finally {
      if (mounted) setState(() => _isOpeningGallery = false);
    }
  }

  bool _hasChanges(ProfileModel profile) {
    final nameChanged = _nameController.text.trim() != (profile.fullName ?? '');
    final usernameChanged = _usernameController.text.trim() != profile.userName;
    final bioChanged = _bioController.text.trim() != (profile.bio ?? '');
    final taglineChanged = _taglineController.text.trim() != (profile.tagline ?? '');
    final countryChanged = _selectedCountryCode != profile.countryCode;

    return nameChanged || usernameChanged || bioChanged || taglineChanged || countryChanged;
  }

  void _saveChanges(BuildContext context) {
    context.read<ProfileCubit>().updateProfile(
          fullName: _nameController.text.trim(),
          userName: _usernameController.text.trim(),
          bio: _bioController.text.trim(),
          tagline: _taglineController.text.trim(),
          countryCode: _selectedCountryCode,
        );
  }

  Widget _buildFlag(String? code, {double size = 24}) {
    if (code == null || code == 'GL') {
      return Text('🌐', style: TextStyle(fontSize: size));
    }
    return SizedBox(
      width: size * 1.4,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CountryFlag.fromCountryCode(code),
      ),
    );
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
                    leading: _buildFlag(country.code, size: 20),
                    title: Text(country.name, style: const TextStyle(color: Colors.white)),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
                    onTap: () {
                      setState(() => _selectedCountryCode = country.code);
                      Navigator.pop(context);
                      _onFieldChanged();
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

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProfileCubit, ProfileState>(
      listener: (context, state) {
        if (state is ProfileLoaded) {
          if (!_initialized) {
            _initialUsername = state.profile.userName;
            _usernameController.text = state.profile.userName;
            _nameController.text = state.profile.fullName ?? '';
            _bioController.text = state.profile.bio ?? '';
            _taglineController.text = state.profile.tagline ?? '';
            _selectedCountryCode = state.profile.countryCode;
            _initialized = true;
          }

          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error!),
                backgroundColor: Colors.red,
              ),
            );
          } else if (_uploadingAvatar && !state.isUpdating) {
            setState(() => _uploadingAvatar = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile photo updated')),
            );
          }
        }
      },
      builder: (context, state) {
        if (state is ProfileLoading || state is ProfileInitial) {
          return const Scaffold(
            backgroundColor: AppColors.primaryBackground,
            body: Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }

        if (state is ProfileError) {
          return Scaffold(
            backgroundColor: AppColors.primaryBackground,
            body: Center(
              child: Text(
                'Error: ${state.message}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }

        final profile = (state as ProfileLoaded).profile;
        final isUpdating = state.isUpdating;

        return Scaffold(
          backgroundColor: AppColors.primaryBackground,
          appBar: AppBar(
            backgroundColor: AppColors.primaryBackground,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            title: Text(
              'Edit Profile',
              style: AppTypography.interTight(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: IconButton(
                  icon: _buildFlag(_selectedCountryCode, size: 24),
                  tooltip: 'Select Country',
                  onPressed: isUpdating ? null : () => _showCountryPicker(context),
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                child: Column(
                  children: [
                    // Avatar section
                    Center(
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: isUpdating ? null : () => _pickImage(context),
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: AppColors.tertiary, width: 2),
                                color: AppColors.tertiary.withValues(alpha: 0.3),
                                image: profile.avatarUrl != null
                                    ? DecorationImage(
                                        image: NetworkImage(profile.avatarUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: profile.avatarUrl == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 50,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: (_isOpeningGallery || isUpdating)
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.camera_alt,
                                      size: 20,
                                      color: Colors.black,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Form inputs
                    TextField(
                      label: 'USERNAME',
                      hintText: 'Enter your username',
                      controller: _usernameController,
                      enabled: !isUpdating,
                      prefixIcon: const Icon(Icons.alternate_email, color: Colors.white24, size: 18),
                      suffixIcon: _isCheckingUsername
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24),
                              ),
                            )
                          : (_isUsernameAvailable == true
                              ? const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
                              : (_isUsernameAvailable == false
                                  ? const Icon(Icons.error, color: Colors.redAccent, size: 20)
                                  : null)),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      label: 'FULL NAME',
                      hintText: 'Enter your full name',
                      controller: _nameController,
                      enabled: !isUpdating,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      label: 'STATUS',
                      hintText: 'How are you feeling?',
                      controller: _taglineController,
                      enabled: !isUpdating,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      label: 'BIO',
                      hintText: 'Tell us about yourself',
                      controller: _bioController,
                      enabled: !isUpdating,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 64),

                    // Delete Account
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.1)),
                      ),
                      child: InkWell(
                        onTap: isUpdating ? null : () => _showDeleteConfirmation(context),
                        borderRadius: BorderRadius.circular(12),
                        hoverColor: Colors.redAccent.withValues(alpha: 0.05),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              'Delete Account',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

              // Sticky Save Button
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  offset: _hasChanges(profile) ? Offset.zero : const Offset(0, 1),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _hasChanges(profile) ? 1.0 : 0.0,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.primaryBackground.withValues(alpha: 0.0),
                            AppColors.primaryBackground,
                          ],
                        ),
                      ),
                      child: PrimaryButton(
                        icon: isUpdating ? null : Icons.check,
                        text: isUpdating ? 'Saving...' : 'Save Changes',
                        onPressed: (isUpdating || _isCheckingUsername || _isUsernameAvailable == false)
                            ? null
                            : () => _saveChanges(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    final confirmController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          backgroundColor: AppColors.primaryBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
              SizedBox(width: 10),
              Text('Delete Account?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes your profile, tickets and event history. This cannot be undone.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              const Text(
                'Type DELETE to confirm:',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: confirmController,
                style: const TextStyle(
                  color: Colors.white,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  hintStyle: const TextStyle(color: Colors.white12),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.redAccent, width: 1),
                  ),
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            TextButton(
              onPressed: confirmController.text == 'DELETE'
                  ? () async {
                      Navigator.pop(dialogContext);
                      try {
                        await context.read<ProfileCubit>().deleteAccount();
                      } catch (_) {}
                    }
                  : null,
              child: Text(
                'Delete Forever',
                style: TextStyle(
                  color: confirmController.text == 'DELETE'
                      ? Colors.redAccent
                      : Colors.redAccent.withValues(alpha: 0.3),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    ).then((_) => confirmController.dispose());
  }
}
