import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lynk_core/src/theme/app_colors.dart';
import 'package:lynk_core/system_config/cubit/system_config_cubit.dart';
import 'dart:io' show Platform;

class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SystemConfigCubit, SystemConfigState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.system_update,
                    size: 80, color: AppColors.primary),
                const SizedBox(height: 24),
                const Text(
                  'Update Required',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'A new version of Lynk-X is available. To continue using the app, please update to the latest version.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () async {
                      final urlKey = Platform.isAndroid
                          ? 'store_url_android'
                          : 'store_url_ios';
                      final urlString = state.getString(urlKey);

                      if (urlString.isNotEmpty) {
                        final url = Uri.parse(urlString);
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url,
                              mode: LaunchMode.externalApplication);
                        }
                      }
                    },
                    child: const Text('Update Now'),
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
