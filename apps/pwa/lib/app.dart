import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lynk_core/core.dart';
import 'router.dart';
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
      child: LynkXApp(locale: _locale),
    );
  }
}

class LynkXApp extends StatefulWidget {
  final Locale? locale;
  const LynkXApp({super.key, this.locale});

  @override
  State<LynkXApp> createState() => _LynkXAppState();
}

class _LynkXAppState extends State<LynkXApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // Initialize the router with combined refresh streams
    _router = createRouter(
      Supabase.instance.client.auth.onAuthStateChange,
      context.read<ProfileCubit>().stream,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      title: 'Lynk-X',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      locale: widget.locale,
      supportedLocales: const [
        Locale('en', ''),
        Locale('sw', ''),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
