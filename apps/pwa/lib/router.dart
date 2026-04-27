import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';

import 'router_refresh_stream.dart';
import 'package:lynk_x/presentation/features/homepage/screens/home_screen.dart';
import 'package:lynk_x/presentation/features/profile/screens/profile_screen.dart';
import 'package:lynk_x/presentation/features/forum/screens/forum_screen.dart';
import 'package:lynk_x/presentation/features/notifications/screens/notifications_screen.dart';
import 'package:lynk_x/presentation/features/ticket/screens/ticket_screen.dart';
import 'package:lynk_x/presentation/features/ticket/screens/tickets_list_screen.dart';
import 'package:lynk_x/presentation/features/profile/screens/edit_profile_screen.dart';
import 'package:lynk_x/presentation/features/profile/screens/profile_setup_screen.dart';
import 'package:lynk_x/presentation/features/feedback/screens/feedback_screen.dart';
import 'package:lynk_x/presentation/features/splashscreen/screens/splash_screen.dart';
import 'package:lynk_x/presentation/features/wallet/screens/wallet_screen.dart';
import 'package:lynk_x/presentation/features/kyc/screens/kyc_verification_screen.dart';
import 'package:lynk_x/presentation/features/subscription/screens/subscription_screen.dart';
import 'package:lynk_x/presentation/shared/screens/system_error_screen.dart';

GoRouter createRouter(
  Stream<AuthState> authStream,
  Stream<ProfileState> profileStream,
  Stream<dynamic> featureFlagStream,
) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: GoRouterRefreshStream([authStream, profileStream, featureFlagStream]),
    redirect: (context, state) {
      try {
        // Safe check for Supabase initialization
        User? user;
        try {
          user = Supabase.instance.client.auth.currentUser;
        } catch (_) {
          // Supabase not initialized or auth failed
        }

        final path = state.uri.toString();

        // Safe check for ProfileCubit
        ProfileState? profileState;
        try {
          profileState = context.read<ProfileCubit>().state;
        } catch (_) {
          // ProfileCubit not found in context
        }

        const publicRoutes = {
          '/auth',
          '/splash',
          '/forgot-password',
          '/reset-password',
          '/verify-email',
          '/maintenance',
          '/error'
        };
        final isPublic = publicRoutes.any((r) => path.startsWith(r));

        // ── Feature-flag kill-switches (evaluated once flags have loaded) ──
        try {
          final flagCubit = context.read<FeatureFlagCubit>();
          if (!flagCubit.state.isLoading && flagCubit.state.flags.isNotEmpty) {
            if (flagCubit.isEnabled('maintenance_mode') && path != '/maintenance') {
              return '/maintenance';
            }
            if (flagCubit.isEnabled('force_app_update') && path != '/update-required') {
              return '/update-required';
            }
          }
        } catch (_) {}

        if (user == null && !isPublic) return '/auth';
        if (user != null && path == '/auth') return '/';

        // ── Onboarding / Profile Setup Redirection ──
        if (user != null && !isPublic && path != '/profile-setup') {
          if (profileState is ProfileLoaded &&
              profileState.profile.isIncomplete) {
            return '/profile-setup';
          }
        }
      } catch (e) {
        debugPrint('[Router] Redirect error: $e');
      }

      return null;
    },
    routes: [
      GoRoute(path: '/auth', builder: (_, __) => const AuthPage()),
      GoRoute(
        path: '/verify-email',
        builder: (_, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          return VerifyEmailPage(email: email);
        },
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, __) => const ResetPasswordPage(),
      ),
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/', builder: (_, __) => const HomePage()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
      GoRoute(
        path: '/forum/:id',
        builder: (_, state) {
          final forumId = state.pathParameters['id']!;
          return ForumPage(forumId: forumId);
        },
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsPage(),
      ),
      GoRoute(
        path: '/ticket/:id',
        builder: (_, state) {
          final ticketId = state.pathParameters['id']!;
          return TicketPage(ticketId: ticketId);
        },
      ),
      GoRoute(
        path: '/tickets',
        builder: (_, __) => const TicketsListScreen(),
      ),
      GoRoute(
        path: '/wallet',
        builder: (context, __) {
          if (!context.read<FeatureFlagCubit>().isEnabled('enable_wallet')) {
            return const SystemErrorScreen(
              title: 'Feature Unavailable',
              message: 'The wallet is not available in your region yet.',
            );
          }
          return const WalletPage();
        },
      ),
      GoRoute(
          path: '/edit-profile', builder: (_, __) => const EditProfilePage()),
      GoRoute(path: '/feedback', builder: (_, __) => const FeedbackScreen()),
      GoRoute(
        path: '/update-required',
        builder: (_, __) => const UpdateRequiredPage(),
      ),
      GoRoute(
        path: '/profile-setup',
        builder: (_, __) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: '/kyc',
        builder: (context, __) {
          if (!context.read<FeatureFlagCubit>().isEnabled('enable_kyc')) {
            return const SystemErrorScreen(
              title: 'Feature Unavailable',
              message: 'Identity verification is not available in your region yet.',
            );
          }
          return const KycVerificationScreen();
        },
      ),
      GoRoute(
        path: '/upgrade',
        builder: (context, __) {
          if (!context.read<FeatureFlagCubit>().isEnabled('enable_premium_subscriptions')) {
            return const SystemErrorScreen(
              title: 'Feature Unavailable',
              message: 'Premium subscriptions are not available yet.',
            );
          }
          return const SubscriptionScreen();
        },
      ),
      GoRoute(
        path: '/maintenance',
        builder: (_, __) => const SystemErrorScreen(
          title: 'Under Maintenance',
          message: 'Lynk-X is currently undergoing scheduled maintenance to improve our systems. We\'ll be back online shortly.',
          isMaintenance: true,
        ),
      ),
      GoRoute(
        path: '/error',
        builder: (_, state) {
          final extras = state.extra as Map<String, dynamic>?;
          return SystemErrorScreen(
            title: extras?['title'] ?? 'Something went wrong',
            message: extras?['message'] ?? 'We are currently experiencing some technical difficulties.',
          );
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.link_off, color: Colors.white24, size: 64),
            const SizedBox(height: 24),
            const Text(
              'Page not found',
              style: TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              state.uri.toString(),
              style: const TextStyle(color: Colors.white30, fontSize: 13),
            ),
            const SizedBox(height: 32),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Go home', style: TextStyle(color: Color(0xFF00FF00))),
            ),
          ],
        ),
      ),
    ),
  );
}
