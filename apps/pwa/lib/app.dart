import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'router.dart';
import 'package:lynk_x/presentation/features/profile/cubit/profile_cubit.dart';
import 'package:lynk_x/presentation/features/profile/cubit/profile_state.dart';
import 'package:lynk_x/presentation/features/notifications/cubit/notification_cubit.dart';
import 'package:lynk_x/presentation/features/wallet/cubit/wallet_cubit.dart';
import 'package:lynk_x/l10n/app_localizations.dart';

class LynkXAppWrapper extends StatefulWidget {
  const LynkXAppWrapper({super.key});

  static void setLocale(BuildContext context, Locale newLocale) {
    _LynkXAppWrapperState? state =
        context.findAncestorStateOfType<_LynkXAppWrapperState>();
    state?.setLocale(newLocale);
  }

  @override
  State<LynkXAppWrapper> createState() => _LynkXAppWrapperState();
}

class _LynkXAppWrapperState extends State<LynkXAppWrapper> {
  Locale? _locale;

  void setLocale(Locale locale) {
    setState(() => _locale = locale);
  }

  @override
  Widget build(BuildContext context) {
    return LynkXApp(locale: _locale);
  }
}

class LynkXApp extends StatelessWidget {
  final Locale? locale;
  const LynkXApp({super.key, this.locale});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => FeatureFlagCubit()..init()),
        BlocProvider(create: (context) => SystemConfigCubit()..init()),
        BlocProvider(create: (context) => BlockCubit()..init()),
        BlocProvider(create: (context) => ProfileCubit()..loadProfile()),
        BlocProvider(
          create: (context) => NotificationCubit()..loadNotifications(),
        ),
        BlocProvider(create: (context) => WalletCubit()),
      ],
      child: BlocListener<ProfileCubit, ProfileState>(
        listener: (context, state) {
          if (state is ProfileLoaded && state.profile.isIncomplete) {
            appRouter.go('/profile-setup');
          }
        },
        child: MaterialApp.router(
          title: 'Lynk-X',
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.darkTheme,
          routerConfig: appRouter,
        ),
      ),
    );
  }
}
