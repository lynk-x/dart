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
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'services/push_notification_service.dart';
import 'package:lynk_x/core/utils/embedding_manager.dart';

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
        BlocProvider(
            create: (context) =>
                ProfileCubit(profileRepository)..loadProfile()),
        // NotificationCubit is NOT auto-loaded here — it force-unwraps
        // currentUser, which is null on a cold start before auth resolves.
        // loadNotifications() is triggered from the signedIn auth event instead.
        BlocProvider(
            create: (context) => NotificationCubit(notificationRepository)),
        BlocProvider(create: (context) => WalletCubit(walletRepository)),
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
  late GoRouter _router;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<FeatureFlagState>? _featureFlagSubscription;
  bool _isSupabaseInitialized = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkSupabaseInitialization();
  }

  void _checkSupabaseInitialization() {
    try {
      Supabase.instance.client;
      _isSupabaseInitialized = true;
    } catch (_) {
      _isSupabaseInitialized = false;
    }

    if (_isSupabaseInitialized) {
      _initApp();
    }
  }

  void _initApp() {
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
      context.read<FeatureFlagCubit>().stream,
    );

    // Wire push notification taps to GoRouter
    PushNotificationService.instance.onNotificationTap = (route) {
      if (_isSupabaseInitialized) {
        _router.go(route);
      }
    };

    // Initialize and listen to the client embedding feature flag
    final featureFlags = context.read<FeatureFlagCubit>();
    _featureFlagSubscription = featureFlags.stream.listen((state) {
      EmbeddingManager.instance.init(
        isEnabled: featureFlags.isEnabled('enable_client_embeddings'),
      );
    });

    // Inform the user when notification permission is denied so they know
    // why they won't receive alerts.
    PushNotificationService.instance.onPermissionDenied = () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications are disabled. Enable them in your browser settings to receive alerts.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    };

    // Auth state listener — handles sign-in, sign-out, and password recovery.
    try {
      _authSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.event == AuthChangeEvent.initialSession ||
            data.event == AuthChangeEvent.signedIn) {
          if (!mounted) return;
          context.read<ProfileCubit>().loadProfile();
          context.read<NotificationCubit>().loadNotifications();
          PushNotificationService.instance.init();
        } else if (data.event == AuthChangeEvent.tokenRefreshed) {
          // Session token was silently refreshed (e.g. app foregrounded after
          // expiry). Re-sync profile and wallet so they hold fresh data.
          if (!mounted) return;
          context.read<ProfileCubit>().loadProfile();
          context.read<WalletCubit>().refresh();
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

  Future<void> _retryInitialization() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    // Re-check or re-attempt Supabase initialization
    try {
      Supabase.instance.client;
      _isSupabaseInitialized = true;
    } catch (_) {
      const supabaseUrl = String.fromEnvironment('NEXT_PUBLIC_SUPABASE_URL');
      const supabaseAnonKey = String.fromEnvironment('NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY');
      if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
        try {
          await Supabase.initialize(
              url: supabaseUrl, publishableKey: supabaseAnonKey);
          _isSupabaseInitialized = true;
        } catch (_) {
          _isSupabaseInitialized = false;
        }
      } else {
        _isSupabaseInitialized = false;
      }
    }

    if (_isSupabaseInitialized) {
      _initApp();
    } else {
      await Future.delayed(const Duration(seconds: 1));
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _featureFlagSubscription?.cancel();
    super.dispose();
  }

  Widget _buildDegradedAppScreen() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0x1120F928),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x3320F928)),
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    color: Color(0xFF20F928),
                    size: 64,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Connection Issues',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'We are having trouble connecting to our services. The server might be temporarily offline or your network connection might be unstable.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: Colors.white54,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),
                if (_isLoading)
                  const CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF20F928)),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _retryInitialization,
                    icon:
                        const Icon(Icons.refresh_rounded, color: Colors.black),
                    label: const Text(
                      'Retry Connection',
                      style: TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF20F928),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupabaseInitialized) {
      return _buildDegradedAppScreen();
    }

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
