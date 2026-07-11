import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';

import 'router_refresh_stream.dart';
import 'package:lynk_x/presentation/features/homepage/screens/home_screen.dart';

import 'package:lynk_x/presentation/features/forum/screens/forum_screen.dart';
import 'package:lynk_x/presentation/features/forum/screens/sessions_screen.dart';
import 'package:lynk_x/presentation/features/forum/widgets/ticket_scanner_sheet.dart';
import 'package:lynk_x/presentation/features/forum/cubit/ticket_validation_cubit.dart';
import 'package:lynk_x/presentation/features/notifications/screens/notifications_screen.dart';
import 'package:lynk_x/presentation/features/auth/screens/claim_bridge_screen.dart';
import 'package:lynk_x/presentation/features/ticket/screens/ticket_screen.dart';
import 'package:lynk_x/presentation/features/ticket/screens/tickets_list_screen.dart';
import 'package:lynk_x/presentation/features/profile/screens/edit_profile_screen.dart';
import 'package:lynk_x/presentation/features/profile/screens/profile_setup_screen.dart';
import 'package:lynk_x/presentation/features/profile/screens/account_screen.dart';
import 'package:lynk_x/presentation/features/feedback/screens/feedback_screen.dart';
import 'package:lynk_x/presentation/features/support/screens/support_screen.dart';
import 'package:lynk_x/presentation/features/support/screens/live_chat_screen.dart';

import 'package:lynk_x/presentation/features/wallet/screens/wallet_screen.dart';
import 'package:lynk_x/presentation/features/wallet/screens/wallet_list_screen.dart';
import 'package:lynk_x/presentation/features/wallet/screens/wallet_transactions_screen.dart';
import 'package:lynk_x/presentation/features/wallet/screens/wallet_history_screen.dart';
import 'package:lynk_x/presentation/features/wallet/screens/wallet_settings_screen.dart';
import 'package:lynk_x/presentation/features/wallet/screens/payment_methods_screen.dart';
import 'package:lynk_x/presentation/features/wallet/widgets/wallet_security_gate.dart';
import 'package:lynk_x/presentation/features/kyc/screens/kyc_verification_screen.dart';
import 'package:lynk_x/presentation/features/subscription/screens/subscription_screen.dart';
import 'package:lynk_x/presentation/shared/screens/system_error_screen.dart';

GoRouter createRouter(
  Stream<AuthState> authStream,
  Stream<ProfileState> profileStream,
  Stream<dynamic> featureFlagStream,
) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable:
        GoRouterRefreshStream([authStream, profileStream, featureFlagStream]),
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

        // '/auth/bridge' is deliberately NOT public: checkout now signs the
        // buyer into a real account via phone+OTP, so opening this link
        // while signed out should hit the normal '/auth' gate below (not
        // bootstrap an anonymous session, which the bridge screen no longer
        // does at all).
        const publicRoutes = {
          '/auth',
          '/maintenance',
          '/error'
        };
        final isPublic = publicRoutes.any((r) => path.startsWith(r));

        // ── Feature-flag kill-switches (evaluated once flags have loaded) ──
        try {
          final flagCubit = context.read<FeatureFlagCubit>();
          if (!flagCubit.state.isLoading && flagCubit.state.flags.isNotEmpty) {
            if (flagCubit.isEnabled('app_maintenance_mode') &&
                path != '/maintenance') {
              return '/maintenance';
            }
            if (flagCubit.isEnabled('force_app_update') &&
                path != '/update-required') {
              return '/update-required';
            }
          }
        } catch (_) {}

        if (user == null && !isPublic) {
          // Carry the originally-requested path through sign-in so routes
          // that require auth (e.g. '/auth/bridge', reached from the
          // checkout confirmation "Enter Event Forum" link) return the
          // visitor to where they meant to go instead of dropping them at
          // the home screen after verifying their OTP.
          return '/auth?next=${Uri.encodeComponent(path)}';
        }
        if (user != null && path == '/auth') {
          final next = state.uri.queryParameters['next'];
          return (next != null && next.isNotEmpty) ? next : '/';
        }

        // ── Onboarding / Profile Setup Redirection ──
        if (user != null && !isPublic && !path.startsWith('/profile-setup')) {
          if (profileState is ProfileLoaded &&
              profileState.profile.isIncomplete) {
            return '/profile-setup?next=${Uri.encodeComponent(path)}';
          }
        }
      } catch (e) {
        debugPrint('[Router] Redirect error: $e');
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (_, __) => Title(
          title: 'Access Account',
          color: Colors.black,
          child: const AuthPage(),
        ),
      ),
      GoRoute(
        path: '/auth/bridge',
        builder: (_, state) {
          final forumReference = state.uri.queryParameters['forum_reference'];
          return Title(
            title: 'Opening Forum',
            color: Colors.black,
            child: ClaimBridgeScreen(forumReference: forumReference),
          );
        },
      ),
      GoRoute(
        path: '/',
        builder: (_, __) => Title(
          title: 'Home',
          color: Colors.black,
          child: const HomePage(),
        ),
      ),

      GoRoute(
        path: '/forum/:reference',
        builder: (_, state) {
          final forumReference = state.pathParameters['reference']!;
          return Title(
            title: 'Forum',
            color: Colors.black,
            child: ForumPage(forumReference: forumReference),
          );
        },
        routes: [
          GoRoute(
            path: 'sessions',
            builder: (context, state) {
              final forumReference = state.pathParameters['reference']!;
              final extras = state.extra as Map<String, dynamic>?;
              final isOrganizer = extras?['isOrganizer'] as bool? ?? false;
              final forumId = state.uri.queryParameters['forumId'] ?? extras?['forumId'] as String?;
              final forumCreatedAtRaw = state.uri.queryParameters['createdAt'] ?? extras?['forumCreatedAt'];
              final forumCreatedAt = forumCreatedAtRaw != null
                  ? (forumCreatedAtRaw is DateTime
                      ? forumCreatedAtRaw
                      : DateTime.parse(forumCreatedAtRaw.toString()))
                  : null;

              return Title(
                title: 'Sessions',
                color: Colors.black,
                child: SessionsScreen(
                  forumId: forumId,
                  isOrganizer: isOrganizer,
                  forumCreatedAt: forumCreatedAt,
                  forumReference: forumReference,
                ),
              );
            },
          ),
          GoRoute(
            path: 'scanner',
            builder: (context, state) {
              final extras = state.extra as Map<String, dynamic>?;
              final eventId = state.uri.queryParameters['eventId'] ?? extras?['eventId'] as String?;
              final eventCreatedAtRaw = state.uri.queryParameters['eventCreatedAt'] ?? extras?['eventCreatedAt'];
              final eventCreatedAt = eventCreatedAtRaw != null
                  ? (eventCreatedAtRaw is DateTime
                      ? eventCreatedAtRaw
                      : DateTime.parse(eventCreatedAtRaw.toString()))
                  : null;

              if (eventId == null || eventCreatedAt == null) {
                return Title(
                  title: 'Error',
                  color: Colors.black,
                  child: const SystemErrorScreen(
                    title: 'Invalid Event',
                    message: 'Cannot launch scanner without a valid event reference.',
                  ),
                );
              }

              return Title(
                title: 'Ticket Scanner',
                color: Colors.black,
                child: BlocProvider<TicketValidationCubit>(
                  create: (context) => TicketValidationCubit(
                    eventId: eventId,
                    eventCreatedAt: eventCreatedAt,
                  )..fetchTickets(),
                  child: Scaffold(
                    backgroundColor: Colors.black,
                    body: TicketScannerSheet(
                      eventId: eventId,
                      eventCreatedAt: eventCreatedAt,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => Title(
          title: 'Notifications',
          color: Colors.black,
          child: const NotificationsPage(),
        ),
      ),
      GoRoute(
        path: '/ticket/:reference',
        builder: (_, state) {
          final ticketReference = state.pathParameters['reference']!;
          return Title(
            title: 'Ticket Details',
            color: Colors.black,
            child: TicketPage(ticketReference: ticketReference),
          );
        },
      ),
      GoRoute(
        path: '/tickets',
        builder: (_, __) => Title(
          title: 'My Tickets',
          color: Colors.black,
          child: const TicketsListScreen(),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) {
          if (!context.read<FeatureFlagCubit>().isEnabled('enable_wallet')) {
            return Title(
              title: 'Feature Unavailable',
              color: Colors.black,
              child: const SystemErrorScreen(
                title: 'Feature Unavailable',
                message: 'The wallet is not available in your region yet.',
              ),
            );
          }
          return WalletSecurityGate(child: child);
        },
        routes: [
          GoRoute(
            path: '/wallet',
            builder: (context, state) {
              final pay = state.uri.queryParameters['pay'];
              return Title(
                title: 'My Wallet',
                color: Colors.black,
                child: WalletPage(prefilledRecipientId: pay),
              );
            },
            routes: [
              GoRoute(
                path: 'list',
                builder: (_, __) => Title(
                  title: 'Currencies',
                  color: Colors.black,
                  child: const WalletListPage(),
                ),
                routes: [
                  GoRoute(
                    path: ':currency',
                    builder: (context, state) {
                      final currency = state.pathParameters['currency']!;
                      return Title(
                        title: '${currency.toUpperCase()} Transactions',
                        color: Colors.black,
                        child: WalletTransactionsPage(currency: currency),
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'history',
                builder: (_, __) => Title(
                  title: 'Transaction History',
                  color: Colors.black,
                  child: const WalletHistoryPage(),
                ),
              ),
              GoRoute(
                path: 'settings',
                builder: (_, __) => Title(
                  title: 'Wallet Settings',
                  color: Colors.black,
                  child: const WalletSettingsPage(),
                ),
              ),
              GoRoute(
                path: 'payment-methods',
                builder: (_, __) => Title(
                  title: 'Payment Methods',
                  color: Colors.black,
                  child: const PaymentMethodsScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/edit-profile',
        builder: (_, __) => Title(
          title: 'Edit Profile',
          color: Colors.black,
          child: const EditProfilePage(),
        ),
      ),
      GoRoute(
        path: '/account',
        builder: (_, __) => Title(
          title: 'Manage Account',
          color: Colors.black,
          child: const AccountPage(),
        ),
      ),
      GoRoute(
        path: '/feedback',
        builder: (_, __) => Title(
          title: 'Feedback',
          color: Colors.black,
          child: const FeedbackScreen(),
        ),
      ),
      GoRoute(
        path: '/support',
        builder: (context, state) {
          final supportContext = state.uri.queryParameters['context'];
          return Title(
            title: 'Support',
            color: Colors.black,
            child: SupportScreen(
              supportContext: supportContext != null
                  ? SupportContext.values.firstWhere(
                      (e) => e.name == supportContext,
                      orElse: () => SupportContext.general,
                    )
                  : SupportContext.general,
            ),
          );
        },
        routes: [
          GoRoute(
            path: 'chat',
            builder: (context, state) {
              final extras = state.extra as Map<String, dynamic>?;
              final ticketId = extras?['ticketId'] as String?;
              final supportContextName =
                  state.uri.queryParameters['context'] ?? 'general';
              final supportContext = SupportContext.values.firstWhere(
                (e) => e.name == supportContextName,
                orElse: () => SupportContext.general,
              );
              return Title(
                title: 'Live Chat',
                color: Colors.black,
                child: LiveChatScreen(
                  supportContext: supportContext,
                  ticketId: ticketId,
                ),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/update-required',
        builder: (_, __) => Title(
          title: 'App Update Required',
          color: Colors.black,
          child: const UpdateRequiredPage(),
        ),
      ),
      GoRoute(
        path: '/profile-setup',
        builder: (_, state) => Title(
          title: 'Profile Onboarding',
          color: Colors.black,
          child: ProfileSetupScreen(next: state.uri.queryParameters['next']),
        ),
      ),
      GoRoute(
        path: '/pay/:recipientId',
        redirect: (context, state) {
          final recipientId = state.pathParameters['recipientId'];
          return '/wallet?pay=$recipientId';
        },
      ),
      GoRoute(
        path: '/kyc',
        builder: (context, __) {
          if (!context.read<FeatureFlagCubit>().isEnabled('enable_kyc')) {
            return Title(
              title: 'Feature Unavailable',
              color: Colors.black,
              child: const SystemErrorScreen(
                title: 'Feature Unavailable',
                message:
                    'Identity verification is not available in your region yet.',
              ),
            );
          }
          return Title(
            title: 'Identity Verification',
            color: Colors.black,
            child: const KycVerificationScreen(),
          );
        },
      ),
      GoRoute(
        path: '/upgrade',
        builder: (context, __) {
          if (!context
              .read<FeatureFlagCubit>()
              .isEnabled('enable_premium_subscriptions')) {
            return Title(
              title: 'Feature Unavailable',
              color: Colors.black,
              child: const SystemErrorScreen(
                title: 'Feature Unavailable',
                message: 'Premium subscriptions are not available yet.',
              ),
            );
          }
          return Title(
            title: 'Upgrade',
            color: Colors.black,
            child: const SubscriptionScreen(),
          );
        },
      ),
      GoRoute(
        path: '/maintenance',
        builder: (_, __) => Title(
          title: 'Under Maintenance',
          color: Colors.black,
          child: const SystemErrorScreen(
            title: 'Under Maintenance',
            message:
                'Lynk-X is currently undergoing scheduled maintenance to improve our systems. We\'ll be back online shortly.',
            isMaintenance: true,
          ),
        ),
      ),
      GoRoute(
        path: '/error',
        builder: (_, state) {
          final extras = state.extra as Map<String, dynamic>?;
          final titleStr = extras?['title'] ?? 'Something went wrong';
          return Title(
            title: titleStr,
            color: Colors.black,
            child: SystemErrorScreen(
              title: titleStr,
              message: extras?['message'] ??
                  'We are currently experiencing some technical difficulties.',
            ),
          );
        },
      ),
    ],
    errorBuilder: (context, state) => Title(
      title: 'Page Not Found',
      color: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.link_off, color: Colors.white24, size: 64),
              const SizedBox(height: 24),
              const Text(
                'Page not found',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                state.uri.toString(),
                style: const TextStyle(color: Colors.white30, fontSize: 13),
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('Go home',
                    style: TextStyle(color: Color(0xFF00FF00))),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
