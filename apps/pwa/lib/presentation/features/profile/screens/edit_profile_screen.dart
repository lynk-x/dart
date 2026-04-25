import 'dart:async';
import 'package:flutter/material.dart' hide TextField;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/shared/widgets/text_field.dart';
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
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _usernameController.removeListener(_onUsernameChanged);
    _debounceTimer?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _taglineController.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    final name = _usernameController.text.trim();
    if (name == _initialUsername || name.length < 3) {
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
  }

  void _saveChanges(BuildContext context) {
    context.read<ProfileCubit>().updateProfile(
          fullName: _nameController.text.trim(),
          userName: _usernameController.text.trim(),
          bio: _bioController.text.trim(),
          tagline: _taglineController.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProfileCubit, ProfileState>(
      listener: (context, state) {
        if (state is ProfileLoaded) {
          if (!_initialized) {
            _nameController.text = state.profile.fullName ?? '';
            _usernameController.text = state.profile.userName;
            _bioController.text = state.profile.bio ?? '';
            _taglineController.text = state.profile.tagline ?? '';
            _initialUsername = state.profile.userName;
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
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
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
                          child: Icon(
                            isUpdating ? Icons.hourglass_top : Icons.camera_alt,
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
                  label: 'FULL NAME',
                  hintText: 'Enter your full name',
                  controller: _nameController,
                  enabled: !isUpdating,
                ),
                const SizedBox(height: 24),
                TextField(
                  label: 'USERNAME',
                  hintText: 'Enter your username',
                  controller: _usernameController,
                  enabled: !isUpdating,
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
                              : const Icon(Icons.alternate_email, color: Colors.white24, size: 18))),
                ),
                const SizedBox(height: 24),
                TextField(
                  label: 'BIO',
                  hintText: 'Tell us about yourself',
                  controller: _bioController,
                  enabled: !isUpdating,
                  maxLines: 3,
                ),
                const SizedBox(height: 24),
                TextField(
                  label: 'TAGLINE',
                  hintText: 'A short catchy line',
                  controller: _taglineController,
                  enabled: !isUpdating,
                ),
                const SizedBox(height: 48),

                // Save button
                PrimaryButton(
                  icon: isUpdating ? null : Icons.check,
                  text: isUpdating ? 'Saving...' : 'Save Changes',
                  onPressed: (isUpdating || _isCheckingUsername || _isUsernameAvailable == false)
                      ? null
                      : () => _saveChanges(context),
                ),
                const SizedBox(height: 32),

                // Delete Account
                TextButton(
                  onPressed: isUpdating
                      ? null
                      : () => _showDeleteConfirmation(context),
                  child: const Text(
                    'Delete Account',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
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
                'This permanently deletes your profile, tickets, and event history. This cannot be undone.',
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
