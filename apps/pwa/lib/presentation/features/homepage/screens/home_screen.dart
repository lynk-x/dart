import 'package:flutter/material.dart' hide Badge;
import 'package:web/web.dart' as web;
import 'package:badges/badges.dart' as badges;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lynk_core/core.dart';

import 'package:lynk_x/presentation/features/homepage/cubit/home_cubit.dart';
import 'package:lynk_x/presentation/features/homepage/cubit/home_state.dart';
import 'package:lynk_x/presentation/features/homepage/widgets/forum_widget.dart';
import 'package:lynk_x/presentation/features/homepage/widgets/home_drawer.dart';
import 'package:lynk_x/presentation/features/notifications/cubit/notification_cubit.dart';
import 'package:lynk_x/presentation/features/notifications/cubit/notification_state.dart';
import 'package:lynk_x/presentation/features/notifications/widgets/device_notification_modal.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

/// Root entry point for the Home feature.
///
/// Provides a [HomeCubit] to the widget tree and delegates rendering to
/// [HomeView], which owns only the [ScrollController].
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeCubit(eventRepository)..init(),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeviceNotificationModal.checkAndShow(context);
    });
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
    final uri = Uri.parse(kWebAppBaseUrl);
    if (!await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) {
      if (mounted) {
        AppSnackBars.showError(context, 'Could not open the web app.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 1. If the drawer is open, close it first
        final scaffoldState = Scaffold.of(context);
        if (scaffoldState.isDrawerOpen) {
          scaffoldState.closeDrawer();
          return;
        }

        // 2. If there are sub-pages in the router stack, pop them
        final router = GoRouter.of(context);
        if (router.canPop()) {
          router.pop();
          return;
        }

        // 3. Root-level exit: single back-press shows a confirmation modal
        // rather than a double-tap pattern — a modal is unambiguous on its
        // own, so there's no need to make the user press back twice.
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Leave Lynk-X?',
                style: TextStyle(color: Colors.white)),
            content: const Text(
              'You\'ll be taken back to what you were doing before this app.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('Leave',
                    style: TextStyle(
                        color: context.accentColor,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (confirmed != true) return;


        web.window.history.back();
      },
      child: Scaffold(
        backgroundColor: AppColors.primaryBackground,
        drawer: const HomeDrawer(),
        appBar: _buildAppBar(),
        body: BlocBuilder<HomeCubit, HomeState>(
          builder: (context, state) {
            // Full-screen loader on first load
            if (state.isLoading) {
              return Center(
                child: CircularProgressIndicator(color: context.accentColor),
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
                      const Icon(Icons.wifi_off_rounded,
                          size: 48, color: Colors.white24),
                      const SizedBox(height: 16),
                      Text(
                        'Could not load events',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.errorMessage!,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: context.read<HomeCubit>().refresh,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Try again'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.accentColor,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: [
                if (_showWelcomeBanner) _buildWelcomeBanner(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: context.read<HomeCubit>().refresh,
                    color: context.accentColor,
                    backgroundColor: AppColors.tertiary,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (state.events.isEmpty) {
                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            controller: _scrollController,
                            child: Container(
                              height: constraints.maxHeight,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.all(24.0),
                              child: Text(
                                "You haven't joined any events yet.\nBook your first event to get started!",
                                textAlign: TextAlign.center,
                                style: AppTypography.inter(
                                  fontSize: 16,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ),
                          );
                        }

                        final isWide = constraints.maxWidth > 600;

                        if (isWide) {
                          return GridView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 400,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 1.38,
                            ),
                            itemCount: state.events.length +
                                (state.isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == state.events.length) {
                                return Center(
                                  child: CircularProgressIndicator(
                                      color: context.accentColor),
                                );
                              }
                              final event = state.events[index];
                              return RepaintBoundary(
                                key: ValueKey('grid_${event.id}'),
                                child: ForumWidget(
                                  key: ValueKey(event.id),
                                  event: event,
                                  isGrid: true,
                                ),
                              );
                            },
                          );
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: state.events.length +
                              (state.isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            // Bottom pagination spinner
                            if (index == state.events.length) {
                              return Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: context.accentColor,
                                  ),
                                ),
                              );
                            }
                            final event = state.events[index];
                            return RepaintBoundary(
                              key: ValueKey('list_${event.id}'),
                              child: ForumWidget(
                                key: ValueKey(event.id),
                                event: event,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.white12, width: 0.5),
                    ),
                  ),
                  padding: const EdgeInsets.all(16.0),
                  child: PrimaryButton(
                    icon: Icons.search,
                    text: 'Look up new events',
                    onPressed: _launchWebApp,
                  ),
                ),
              ],
            );
          },
        ),
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
            context.accentColor.withValues(alpha: 0.15),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.accentColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: context.accentColor,
            child: Icon(Icons.waving_hand, color: Colors.black, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome to forums!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your event feed is live. Join a forum to chat with attendees or tap an event to explore.',
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
            icon: Icon(Icons.close,
                color: Colors.white.withValues(alpha: 0.3), size: 16),
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
      title: RepaintBoundary(
        child: SvgPicture.asset(
          'assets/images/official_lynk-x_combined-logo.svg',
          width: 200,
          fit: BoxFit.contain,
        ),
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
