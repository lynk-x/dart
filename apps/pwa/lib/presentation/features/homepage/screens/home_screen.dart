import 'package:flutter/material.dart' hide Badge;
import 'package:badges/badges.dart' as badges;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/homepage/cubit/home_cubit.dart';
import 'package:lynk_x/presentation/features/homepage/cubit/home_state.dart';
import 'package:lynk_x/presentation/features/homepage/widgets/forum_widget.dart';
import 'package:lynk_x/presentation/features/homepage/widgets/home_drawer.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';
import 'package:lynk_x/core/utils/breakpoints.dart';
import 'package:lynk_x/presentation/features/notifications/cubit/notification_cubit.dart';
import 'package:lynk_x/presentation/features/notifications/cubit/notification_state.dart';

/// Root entry point for the Home feature.
///
/// Provides a [HomeCubit] to the widget tree and delegates rendering to
/// [HomeView], which owns only the [ScrollController].
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeCubit()..init(),
      child: const HomeView(),
    );
  }
}

/// The main home screen UI.
///
/// Stateful only to manage the [ScrollController] (pure UI lifecycle concern).
/// All business logic (loading, pagination, sorting) lives in [HomeCubit].
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  bool _showWelcomeBanner = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final cubit = context.read<HomeCubit>();
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !cubit.state.isLoadingMore &&
          cubit.state.hasMore) {
        cubit.loadMore();
      }
    });
    _loadWelcomeBanner();
  }

  Future<void> _loadWelcomeBanner() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool('home_welcome_dismissed') ?? false;
    if (mounted && !dismissed) setState(() => _showWelcomeBanner = true);
  }

  Future<void> _dismissWelcomeBanner() async {
    setState(() => _showWelcomeBanner = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('home_welcome_dismissed', true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Launches the web app in the device browser.
  Future<void> _launchWebApp() async {
    final discoveryUrl = context.read<SystemConfigCubit>().state.getString(
          'web_discovery_url',
        );

    final uri = Uri.parse(discoveryUrl);
    if (!await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the web app.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      drawer: const HomeDrawer(),
      appBar: _buildAppBar(),
      body: BlocBuilder<HomeCubit, HomeState>(
        builder: (context, state) {
          // Full-screen loader on first load
          if (state.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          // Surface fetch errors without crashing the whole screen
          if (state.errorMessage != null && state.events.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.white24),
                    const SizedBox(height: 16),
                    Text(
                      'Could not load events',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.errorMessage!,
                      style: const TextStyle(color: Colors.white38, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: context.read<HomeCubit>().refresh,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Try again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state.events.isEmpty && !state.isLoading) {
            return EmptyState(
              message: "You haven't joined any events yet.",
              actionLabel: 'Find Events',
              onAction: _launchWebApp,
            );
          }

          return Column(
            children: [
              if (_showWelcomeBanner) _buildWelcomeBanner(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: context.read<HomeCubit>().refresh,
                  color: AppColors.primary,
                  backgroundColor: AppColors.tertiary,
                  // Centre content and cap width on tablets/desktops
                  child: Breakpoints.constrain(
                    ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount:
                          state.events.length + (state.isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        // Bottom pagination spinner
                        if (index == state.events.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            ),
                          );
                        }
                        return ForumWidget(event: state.events[index]);
                      },
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Breakpoints.constrain(
                  PrimaryButton(
                    icon: Icons.search,
                    text: 'Look up new events',
                    onPressed: _launchWebApp,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary,
            child: Icon(Icons.waving_hand, color: Colors.black, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome to Lynk-X!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your event feed is live. Join a forum to chat with attendees, or tap an event to explore.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.3), size: 16),
            onPressed: _dismissWelcomeBanner,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primaryBackground,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: true,
      leadingWidth: 60,
      leading: Builder(builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: IconButton(
            icon: const Icon(Icons.person, color: Colors.white, size: 32),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        );
      }),
      title: Image.asset(
        'assets/images/lynk-x_combined-logo.png',
        width: 200,
        fit: BoxFit.contain,
      ),
      actions: [
        BlocBuilder<NotificationCubit, NotificationState>(
          builder: (context, state) {
            final unreadCount =
                state is NotificationLoaded ? state.unreadCount : 0;
            return IconButton(
              icon: badges.Badge(
                showBadge: unreadCount > 0,
                badgeContent: null,
                badgeStyle: const badges.BadgeStyle(
                  badgeColor: Colors.red,
                  padding: EdgeInsets.all(4),
                  elevation: 0,
                ),
                position: badges.BadgePosition.topEnd(top: 5, end: 5),
                child: const Icon(
                  Icons.notifications,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              onPressed: () => context.push('/notifications'),
            );
          },
        ),
      ],
    );
  }
}
