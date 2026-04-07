import 'package:flutter/material.dart' hide Badge;
import 'package:badges/badges.dart' as badges;


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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Trigger pagination when the user scrolls near the bottom.
    _scrollController.addListener(() {
      final cubit = context.read<HomeCubit>();
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !cubit.state.isLoadingMore &&
          cubit.state.hasMore) {
        cubit.loadMore();
      }
    });
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
              child: Text(
                'Could not load events: ${state.errorMessage}',
                style: const TextStyle(color: Colors.white54),
                textAlign: TextAlign.center,
              ),
            );
          }

          if (state.events.isEmpty && !state.isLoading) {
            return const EmptyState(message: 'No events found');
          }

          return Column(
            children: [
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

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primaryBackground,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: true,
      leadingWidth: 70,
      leading: Builder(builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(left: 12),
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
