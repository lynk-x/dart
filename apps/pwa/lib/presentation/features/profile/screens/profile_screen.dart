import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:share_plus/share_plus.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  void _shareProfile() {
    Share.share(
      'Check out Lynk-X - The ultimate event platform! Join me at: https://lynk-x.app',
      subject: 'Join me on Lynk-X!',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 32, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Image.asset(
          'assets/images/lynk-x_combined-logo.png',
          width: 200,
          fit: BoxFit.contain,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share, size: 32, color: Colors.white),
            onPressed: _shareProfile,
          ),
        ],
      ),
      body: const Center(
        child: Text(
          'Profile Under Construction',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
