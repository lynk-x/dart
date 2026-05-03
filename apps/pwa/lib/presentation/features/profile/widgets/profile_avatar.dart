import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

class ProfileAvatar extends StatelessWidget {
  final String? avatarUrl;
  final bool isUpdating;
  final bool isUploading;
  final VoidCallback onTap;

  const ProfileAvatar({
    super.key,
    required this.avatarUrl,
    required this.isUpdating,
    required this.isUploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        children: [
          GestureDetector(
            onTap: isUpdating ? null : onTap,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.tertiary, width: 2),
                color: AppColors.tertiary.withValues(alpha: 0.3),
                image: avatarUrl != null
                    ? DecorationImage(
                        image: NetworkImage(avatarUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: avatarUrl == null
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
              decoration: BoxDecoration(
                color: context.accentColor,
                shape: BoxShape.circle,
              ),
              child: (isUploading || isUpdating)
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
    );
  }
}
