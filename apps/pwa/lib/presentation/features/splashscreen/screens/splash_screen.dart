import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FeatureFlagCubit, FeatureFlagState>(
      listener: (context, state) {
        if (!state.isLoading) {
          final cubit = context.read<FeatureFlagCubit>();
          final isMaintenance = cubit.isEnabled('maintenance_mode');
          final isUpdateRequired = state.flags.isNotEmpty && cubit.isEnabled('force_app_update');

          if (isMaintenance) {
            context.go('/maintenance');
          } else if (isUpdateRequired) {
            context.go('/update-required');
          } else {
            context.go('/');
          }
        }
      },
      builder: (context, state) {
        if (!state.isLoading &&
            state.flags.isNotEmpty &&
            context.read<FeatureFlagCubit>().isEnabled('force_app_update')) {
          return const UpdateRequiredPage();
        }

        return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
            ),
          ),
        );
      },
    );
  }
}
