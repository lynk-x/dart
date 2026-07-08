import 'dart:async';
import 'package:flutter/material.dart' hide TextField;
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/shared/widgets/text_field.dart';
import 'package:lynk_x/presentation/shared/utils/permission_acks.dart';
import 'package:country_flags/country_flags.dart';
import '../models/country.dart';
import '../widgets/profile_avatar.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();

  String? _selectedGender;
  DateTime? _selectedDateOfBirth;

  bool _initialized = false;
  String _initialUsername = '';

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
    _debounceTimer?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _genderController.dispose();
    _dobController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    final name = _usernameController.text.trim();
    if (name.toLowerCase() == _initialUsername.toLowerCase() || name.length < 3) {
      return;
    }
    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      context.read<ProfileCubit>().checkUsernameAvailability(name);
    });
  }

   void _onAvatarTap(BuildContext context, ProfileModel profile) {
     if (profile.avatarUrl == null) {
       _pickImage(context);
       return;
     }

     showModalBottomSheet(
       context: context,
       backgroundColor: AppColors.tertiary,
       shape: const RoundedRectangleBorder(
         borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
       ),
       builder: (context) => Container(
         padding: const EdgeInsets.symmetric(vertical: 24),
         child: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             ListTile(
               leading: const Icon(Icons.photo_library_outlined, color: Colors.white),
               title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
               onTap: () {
                 Navigator.pop(context);
                 _pickImage(context);
               },
             ),
             ListTile(
               leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
               title: const Text('Remove Photo', style: TextStyle(color: Colors.redAccent)),
               onTap: () {
                 Navigator.pop(context);
                 context.read<ProfileCubit>().removeAvatar();
               },
             ),
           ],
         ),
       ),
     );
   }

  Future<void> _pickImage(BuildContext context) async {
    await PermissionAcks.ensureAcknowledged(
      context,
      PermissionAckType.media,
      title: 'Access your Media',
      description: 'To update your profile photo, we need access to your device library.',
      icon: Icons.perm_media_rounded,
      actionLabel: 'Allow Access',
      onReady: () => _actuallyPickImage(context),
    );
  }

  Future<void> _actuallyPickImage(BuildContext context) async {
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
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not access gallery: ${e.toFriendlyMessage()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpeningGallery = false);
    }
  }

  bool _hasChanges(ProfileModel profile) {
    final nameChanged = _nameController.text.trim() != (profile.fullName ?? '');
    final usernameChanged = _usernameController.text.trim() != profile.userName;
    final countryChanged = _selectedCountryCode != profile.countryCode;
    final genderChanged = _selectedGender != profile.gender;
    final dobChanged = _selectedDateOfBirth != profile.dateOfBirth;

    return nameChanged || usernameChanged || countryChanged || genderChanged || dobChanged;
  }

  void _saveChanges(BuildContext context) {
    context.read<ProfileCubit>().updateProfile(
          fullName: _nameController.text.trim(),
          userName: _usernameController.text.trim(),
          countryCode: _selectedCountryCode,
          gender: _selectedGender,
          dateOfBirth: _selectedDateOfBirth,
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
                    trailing: isSelected ? Icon(Icons.check_circle, color: context.accentColor) : null,
                    onTap: () {
                      setState(() {
                        _selectedCountryCode = country.code;
                        _countryController.text = country.name;
                      });
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

  String? _getGenderLabel(String? value) {
    if (value == 'male') return 'Male';
    if (value == 'female') return 'Female';
    if (value == 'other') return 'Other';
    if (value == 'prefer_not_to_say') return 'Prefer not to say';
    return null;
  }

  String _getCountryName(String? code) {
    if (code == null) return '';
    for (final country in kSupportedCountries) {
      if (country.code.toUpperCase() == code.toUpperCase()) {
        return country.name;
      }
    }
    return '';
  }

  void _showGenderPicker(BuildContext context) {
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
            Text('Select Gender',
                style: AppTypography.interTight(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Male', style: TextStyle(color: Colors.white)),
              trailing: _selectedGender == 'male' ? Icon(Icons.check_circle, color: context.accentColor) : null,
              onTap: () {
                setState(() {
                  _selectedGender = 'male';
                  _genderController.text = 'Male';
                });
                Navigator.pop(context);
                _onFieldChanged();
              },
            ),
            ListTile(
              title: const Text('Female', style: TextStyle(color: Colors.white)),
              trailing: _selectedGender == 'female' ? Icon(Icons.check_circle, color: context.accentColor) : null,
              onTap: () {
                setState(() {
                  _selectedGender = 'female';
                  _genderController.text = 'Female';
                });
                Navigator.pop(context);
                _onFieldChanged();
              },
            ),
            ListTile(
              title: const Text('Other', style: TextStyle(color: Colors.white)),
              trailing: _selectedGender == 'other' ? Icon(Icons.check_circle, color: context.accentColor) : null,
              onTap: () {
                setState(() {
                  _selectedGender = 'other';
                  _genderController.text = 'Other';
                });
                Navigator.pop(context);
                _onFieldChanged();
              },
            ),
            ListTile(
              title: const Text('Prefer not to say', style: TextStyle(color: Colors.white)),
              trailing: _selectedGender == 'prefer_not_to_say' ? Icon(Icons.check_circle, color: context.accentColor) : null,
              onTap: () {
                setState(() {
                  _selectedGender = 'prefer_not_to_say';
                  _genderController.text = 'Prefer not to say';
                });
                Navigator.pop(context);
                _onFieldChanged();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDobPicker(BuildContext context) async {
    final initialDate = _selectedDateOfBirth ?? DateTime(2000, 1, 1);
    DateTime tempDateTime = initialDate;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext modalContext) => CupertinoTheme(
        data: const CupertinoThemeData(
          brightness: Brightness.dark,
        ),
        child: Container(
          height: 300,
          color: const Color(0xFF1E1E1E),
          child: Column(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF2C2C2C),
                  border: Border(
                    bottom: BorderSide(color: Colors.white12, width: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      child: const Text('Cancel', style: TextStyle(color: Colors.white54, fontSize: 15)),
                      onPressed: () => Navigator.pop(modalContext),
                    ),
                    const Text(
                      'Date of Birth',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    CupertinoButton(
                      child: Text(
                        'Done',
                        style: TextStyle(
                          color: context.accentColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedDateOfBirth = tempDateTime;
                          _dobController.text = DateFormat('yyyy-MM-dd').format(tempDateTime);
                        });
                        _onFieldChanged();
                        Navigator.pop(modalContext);
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  initialDateTime: initialDate,
                  mode: CupertinoDatePickerMode.date,
                  onDateTimeChanged: (DateTime newDateTime) {
                    tempDateTime = newDateTime;
                  },
                ),
              ),
            ],
          ),
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
            _selectedCountryCode = state.profile.countryCode;
            _countryController.text = _getCountryName(_selectedCountryCode);
            _selectedGender = state.profile.gender;
            _genderController.text = _getGenderLabel(_selectedGender) ?? '';
            _selectedDateOfBirth = state.profile.dateOfBirth;
            if (_selectedDateOfBirth != null) {
              _dobController.text = DateFormat('yyyy-MM-dd').format(_selectedDateOfBirth!);
            } else {
              _dobController.text = '';
            }
            _initialized = true;
          }

          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error!),
                backgroundColor: Colors.red,
              ),
            );
          } else {
            if (_uploadingAvatar && !state.isUpdating) {
              setState(() => _uploadingAvatar = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile photo updated')),
              );
            }
          }
        }
      },
      builder: (context, state) {
        if (state is ProfileLoading || state is ProfileInitial) {
          return Scaffold(
            backgroundColor: AppColors.primaryBackground,
            body: Center(
                child: CircularProgressIndicator(color: context.accentColor)),
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

        return PopScope(
          canPop: !_hasChanges(profile),
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            
            final shouldPop = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: AppColors.surface,
                title: const Text('Discard changes?', style: TextStyle(color: Colors.white)),
                content: const Text('You have unsaved changes. Are you sure you want to leave?', style: TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Stay', style: TextStyle(color: Colors.white54)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Discard', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            );

            if (shouldPop == true && context.mounted) {
              context.pop();
            }
          },
          child: Scaffold(
            backgroundColor: AppColors.primaryBackground,
            appBar: AppBar(
              backgroundColor: AppColors.primaryBackground,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () {
                   if (_hasChanges(profile)) {
                     // Trigger PopScope logic via Navigator pop
                     Navigator.maybePop(context);
                   } else {
                     context.pop();
                   }
                },
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
                    icon: const Icon(Icons.settings_outlined, color: Colors.white),
                    tooltip: 'Manage Account',
                    onPressed: isUpdating ? null : () => context.push('/account'),
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
                      ProfileAvatar(
                        avatarUrl: profile.avatarUrl,
                        isUpdating: isUpdating,
                        isUploading: _uploadingAvatar || _isOpeningGallery,
                        onTap: () => _onAvatarTap(context, profile),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        label: 'USERNAME',
                        hintText: 'Enter your username',
                        controller: _usernameController,
                        enabled: !isUpdating,
                        prefixIcon: const Icon(Icons.alternate_email,
                            color: Colors.white24, size: 18),
                        suffixIcon: state.isCheckingUsername
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white24),
                                ),
                              )
                            : (state.isUsernameAvailable == true
                                ? Icon(Icons.check_circle,
                                    color: context.accentColor, size: 20)
                                : (state.isUsernameAvailable == false
                                    ? const Icon(Icons.error,
                                        color: Colors.redAccent, size: 20)
                                    : null)),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        label: 'FULL NAME',
                        hintText: 'Enter your full name',
                        controller: _nameController,
                        enabled: !isUpdating,
                      ),
                      const SizedBox(height: 32),
                                            GestureDetector(
                        onTap: isUpdating ? null : () => _showGenderPicker(context),
                        behavior: HitTestBehavior.opaque,
                        child: IgnorePointer(
                          child: TextField(
                            label: 'GENDER',
                            hintText: 'Select Gender',
                            controller: _genderController,
                            readOnly: true,
                            enabled: !isUpdating,
                            suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: isUpdating ? null : () => _showDobPicker(context),
                        behavior: HitTestBehavior.opaque,
                        child: IgnorePointer(
                          child: TextField(
                            label: 'DATE OF BIRTH',
                            hintText: 'Select Date of Birth',
                            controller: _dobController,
                            readOnly: true,
                            enabled: !isUpdating,
                            suffixIcon: const Icon(Icons.calendar_today_outlined, color: Colors.white54, size: 18),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: isUpdating ? null : () => _showCountryPicker(context),
                        behavior: HitTestBehavior.opaque,
                        child: IgnorePointer(
                          child: TextField(
                            label: 'COUNTRY',
                            hintText: 'Select Country',
                            controller: _countryController,
                            readOnly: true,
                            enabled: !isUpdating,
                            prefixIcon: _selectedCountryCode != null
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(width: 16),
                                      _buildFlag(_selectedCountryCode, size: 18),
                                      const SizedBox(width: 12),
                                    ],
                                  )
                                : null,
                            suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
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
                          onPressed: (isUpdating ||
                                  state.isCheckingUsername ||
                                  state.isUsernameAvailable == false)
                              ? null
                              : () => _saveChanges(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
