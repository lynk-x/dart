import 'dart:async';
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
import 'services/push_notification_service.dart';

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
        // NotificationCubit is NOT auto-loaded here — it force-unwraps
        // currentUser, which is null on a cold start before auth resolves.
        // loadNotifications() is triggered from the signedIn auth event instead.
        BlocProvider(create: (context) => NotificationCubit()),
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
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    // Initialize the router with combined refresh streams. 
    // We protect against Supabase.instance access if not initialized.
    Stream<AuthState> authStream;
    try {
      authStream = Supabase.instance.client.auth.onAuthStateChange;
    } catch (e) {
      debugPrint('[LynkXApp] Supabase Auth stream unavailable: $e');
      authStream = const Stream.empty();
    }

    _router = createRouter(
      authStream,
      context.read<ProfileCubit>().stream,
    );

    // Wire push notification taps to GoRouter
    PushNotificationService.instance.onNotificationTap = (route) {
      _router.go(route);
    };

    // Auth state listener — handles sign-in, sign-out, and password recovery.
    try {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.event == AuthChangeEvent.signedIn) {
          if (!mounted) return;
          context.read<ProfileCubit>().loadProfile();
          context.read<NotificationCubit>().loadNotifications();
          PushNotificationService.instance.init();
        } else if (data.event == AuthChangeEvent.signedOut) {
          if (!mounted) return;
          context.read<ProfileCubit>().reset();
          context.read<NotificationCubit>().reset();
          context.read<WalletCubit>().reset();
          PushNotificationService.instance.removeToken();
        } else if (data.event == AuthChangeEvent.passwordRecovery) {
          _router.go('/reset-password');
        }
      });
    } catch (e) {
      debugPrint('[LynkXApp] Supabase Auth listener failed: $e');
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
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
