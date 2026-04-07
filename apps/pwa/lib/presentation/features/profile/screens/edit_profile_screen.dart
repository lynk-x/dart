import 'dart:io';
import 'package:flutter/material.dart' hide TextField;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lynk_core/core.dart' hide PrimaryButton;
import 'package:lynk_x/presentation/shared/widgets/text_field.dart';
import 'package:lynk_x/presentation/shared/widgets/primary_button.dart';
import 'package:lynk_x/presentation/features/profile/cubit/profile_cubit.dart';
import 'package:lynk_x/presentation/features/profile/cubit/profile_state.dart';

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

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _taglineController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(BuildContext context) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 500,
    );

    if (image != null && context.mounted) {
      context.read<ProfileCubit>().uploadAvatar(File(image.path));
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
            _initialized = true;
          }

          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error!),
                backgroundColor: Colors.red,
              ),
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
                  suffixIcon: const Icon(
                    Icons.alternate_email,
                    color: Colors.white24,
                    size: 18,
                  ),
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
                  onPressed: isUpdating ? null : () => _saveChanges(context),
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
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.primaryBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Account?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This action is permanent and will delete all your profile data and access to your events. Are you absolutely sure?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<ProfileCubit>().deleteAccount();
              context.go('/auth');
            },
            child: const Text(
              'Delete Forever',
              style: TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
