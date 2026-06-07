import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lynk_x/presentation/features/forum/widgets/info_banner.dart';
import 'package:lynk_x/presentation/features/forum/widgets/category_filter_bar.dart';
import 'package:lynk_core/core.dart';

import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_chat_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_ads_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_ads_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_presence_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_presence_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_state.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/widgets/ad_carousel.dart';
import 'package:lynk_x/presentation/features/forum/widgets/forum_header.dart';
import 'package:lynk_x/presentation/features/forum/widgets/presence_drawer.dart';
import 'package:lynk_x/presentation/features/forum/widgets/media_viewer.dart';
import 'package:lynk_x/presentation/features/forum/widgets/tabs/updates_tab.dart';
import 'package:lynk_x/presentation/features/forum/widgets/tabs/live_chat_tab.dart';
import 'package:lynk_x/presentation/features/forum/widgets/tabs/media_tab.dart';
import 'package:lynk_x/presentation/features/forum/widgets/reaction_background.dart';

import 'package:lynk_x/presentation/features/forum/widgets/welcome_banner.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';

class ForumPage extends StatelessWidget {
  /// The forum to display. Provided as a path parameter via `/forum/:id`.
  /// Always non-null — the router guarantees a valid UUID before mounting.
  final String forumId;
  const ForumPage({super.key, required this.forumId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ForumCubit(
        repo: forumRepository,
        forumId: forumId,
      )..init(),
      child: BlocBuilder<ForumCubit, ForumState>(
        buildWhen: (p, c) =>
            p.isPremium != c.isPremium ||
            p.showAds != c.showAds ||
            p.members != c.members,
        builder: (context, state) {
          final mainCubit = context.read<ForumCubit>();
          return MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (context) {
                  final ads = ForumAdsCubit(
                    forumId: mainCubit.forumId,
                    userId: mainCubit.userId,
                    isPremium: !state.showAds,
                  );
                  if (context.read<FeatureFlagCubit>().isEnabled('enable_forum_ads')) {
                    ads.init();
                  }
                  return ads;
                },
              ),
              BlocProvider(
                create: (context) {
                  final cubit = ForumPresenceCubit(
                    forumId: mainCubit.forumId,
                    userId: mainCubit.userId,
                    userName: mainCubit.userName,
                    isOrganizer: state.isOrganizer,
                    isPremium: state.isPremium,
                    channel: mainCubit.channel,
                  );
                  if (context
                      .read<FeatureFlagCubit>()
                      .isEnabled('enable_realtime_presence')) {
                    cubit.init();
                  }
                  return cubit;
                },
              ),
              BlocProvider(
                create: (context) => ForumUpdatesCubit(
                  forumId: mainCubit.forumId,
                  userId: mainCubit.userId,
                  userName: mainCubit.userName,
                  channel: mainCubit.channel,
                )..init(),
              ),
              BlocProvider(
                create: (context) => ForumChatCubit(
                  forumId: mainCubit.forumId,
                  userId: mainCubit.userId,
                  userName: mainCubit.userName,
                  forumCreatedAt: mainCubit.state.forumCreatedAt,
                  repo: forumRepository,
                  channel: mainCubit.channel,
                )..init(),
              ),
              BlocProvider(
                create: (context) => ForumMediaCubit(
                  forumId: mainCubit.forumId,
                  userId: mainCubit.userId,
                  isOrganizer: state.isOrganizer,
                )..init(),
              ),
            ],
            child: const ForumView(),
          );
        },
      ),
    );
  }
}

class ForumView extends StatefulWidget {
  const ForumView({super.key});

  @override
  State<ForumView> createState() => _ForumViewState();
}

class _ForumViewState extends State<ForumView> {
  final ScrollController _updatesScrollController = ScrollController();
  final ScrollController _chatScrollController = ScrollController();
  late final PageController _pageController;
  bool _showWelcome = false;
  final Set<String> _precachedUrls = {};

  @override
  void initState() {
    super.initState();
    final initialTab = context.read<ForumCubit>().state.currentTabIndex;
    _pageController = PageController(initialPage: initialTab);
    _loadBannerState();
  }

  void _precacheMedia(List<ForumMedia> mediaItems) {
    if (!mounted) return;
    // Pre-cache only the first 9 items to save bandwidth but ensure instant grid load
    final itemsToPrecache = mediaItems.take(9);
    for (final item in itemsToPrecache) {
      final url = item.thumbnailUrl ?? item.url;
      if (url.isNotEmpty && !_precachedUrls.contains(url)) {
        _precachedUrls.add(url);
        precacheImage(CachedNetworkImageProvider(url), context);
      }
    }
  }

  Future<void> _loadBannerState() async {
    final forumId = context.read<ForumCubit>().forumId;
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool('forum_banner_dismissed_$forumId') ?? false;
    if (mounted) setState(() => _showWelcome = !dismissed);
  }



  @override
  void dispose() {
    _updatesScrollController.dispose();
    _chatScrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }





  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ForumCubit>();
    return MultiBlocListener(
      listeners: [
        BlocListener<ForumCubit, ForumState>(
          listenWhen: (p, c) => p.showAds != c.showAds,
          listener: (context, state) {
            context.read<ForumAdsCubit>().updatePremiumStatus(!state.showAds);
          },
        ),
        BlocListener<ForumCubit, ForumState>(
          listenWhen: (p, c) => p.waveTrigger != c.waveTrigger,
          listener: (context, state) {
            if (!context.read<FeatureFlagCubit>().isEnabled('enable_social_actions')) return;
            if (state.waveFromName != null && state.waveFromUserId != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Text('👋 ', style: TextStyle(fontSize: 24)),
                      Text('${state.waveFromName} waved at you!'),
                    ],
                  ),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: context.accentColor,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          },
        ),
        BlocListener<ForumMediaCubit, ForumMediaState>(
          listenWhen: (p, c) => p.mediaItems != c.mediaItems,
          listener: (context, state) {
            _precacheMedia(state.mediaItems);
          },
        ),
        BlocListener<ForumCubit, ForumState>(
          listenWhen: (p, c) => p.userName != c.userName,
          listener: (context, state) {
            context.read<ForumPresenceCubit>().updateUserName(state.userName);
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: AppColors.primaryBackground,
        endDrawer: _ForumPresenceDrawerWrapper(forumId: cubit.forumId),
        appBar: _buildAppBar(),
        body: Stack(
          children: [
            NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverToBoxAdapter(
                    child: WelcomeBanner(
                      show: _showWelcome,
                      onDismiss: () async {
                        setState(() => _showWelcome = false);
                        final forumId = context.read<ForumCubit>().forumId;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool(
                            'forum_banner_dismissed_$forumId', true);
                      },
                    ),
                  ),
                  BlocBuilder<ForumCubit, ForumState>(
                    buildWhen: (p, c) => p.isPremium != c.isPremium || p.showAds != c.showAds || p.currentTabIndex != c.currentTabIndex,
                    builder: (context, forumState) {
                      return BlocBuilder<ForumAdsCubit, ForumAdsState>(
                        builder: (context, adsState) {
                          final showBannerAd = context.read<FeatureFlagCubit>().isEnabled('enable_banner_ad');
                          final hasAds = !forumState.isPremium && 
                                        showBannerAd && 
                                        context.read<FeatureFlagCubit>().isEnabled('enable_forum_ads') && 
                                        adsState.ads.isNotEmpty;
                          
                          final adsHeight = hasAds ? 50.0 : 0.0;
                          
                          double extraHeight = 0;
                          Widget? extraHeaderWidgets;
                          
                          if (forumState.currentTabIndex == 0) {
                            final updatesState = context.watch<ForumUpdatesCubit>().state;
                            final updatesCubit = context.read<ForumUpdatesCubit>();
                            final pinned = updatesState.messages.where((m) => m.isPinned).toList();
                            
                            extraHeight += 52.0; // CategoryFilterBar
                            if (pinned.isNotEmpty) {
                              extraHeight += 48.0; // InfoBanner exact calculated height for 2 lines
                            }
                            
                            extraHeaderWidgets = Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ColoredBox(
                                  color: AppColors.primaryBackground,
                                  child: CategoryFilterBar(
                                    selectedCategory: updatesState.selectedCategory,
                                    onSelectionChanged: (cat) => updatesCubit.setCategory(cat),
                                  ),
                                ),
                                if (pinned.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                                    child: InfoBanner(
                                      icon: Icons.push_pin,
                                      text: pinned.first.message.length > 80
                                          ? '${pinned.first.message.substring(0, 80)}…'
                                          : pinned.first.message,
                                    ),
                                  ),
                              ],
                            );
                          }

                          final totalHeaderHeight = 104.0 + adsHeight + extraHeight;
                          return SliverOverlapAbsorber(
                            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                            sliver: SliverPersistentHeader(
                              pinned: true,
                              delegate: _SliverAppBarDelegate(
                                height: totalHeaderHeight, 
                                child: SizedBox(
                                  height: totalHeaderHeight,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                    ForumHeader(
                                      isOrganizer: forumState.isOrganizer,
                                      isReadOnly: forumState.isReadOnly,
                                      forumName: forumState.forumName,
                                      onLockToggle: () {
                                        final messenger = ScaffoldMessenger.of(context);
                                        final nextStatus = forumState.isReadOnly ? 'open' : 'read_only';
                                        cubit.updateForumStatus(nextStatus);
                                        messenger.showSnackBar(SnackBar(
                                          content: Text(forumState.isReadOnly ? 'Chat unlocked' : 'Chat locked'),
                                          behavior: SnackBarBehavior.floating,
                                        ));
                                      },
                                      onSearch: (q) {
                                        context.read<ForumUpdatesCubit>().setSearchQuery(q);
                                        context.read<ForumChatCubit>().setSearchQuery(q);
                                      },
                                      onSearchToggle: () {
                                        final updatesCubit = context.read<ForumUpdatesCubit>();
                                        final chatCubit = context.read<ForumChatCubit>();
                                        if (updatesCubit.state.searchQuery.isNotEmpty || 
                                            chatCubit.state.searchQuery.isNotEmpty) {
                                          updatesCubit.setSearchQuery('');
                                          chatCubit.setSearchQuery('');
                                        }
                                      },
                                    ),
                                    if (hasAds) RepaintBoundary(
                                      child: AdCarousel(
                                        ads: adsState.ads,
                                        onAdViewed: (adId) =>
                                            context.read<ForumAdsCubit>().logAdImpression(adId),
                                        onAdClicked: (ad) async {
                                          context.read<ForumAdsCubit>().logAdClick(ad.id);
                                          if (ad.targetUrl != null) {
                                            final uri = Uri.parse(ad.targetUrl!);
                                            if (await canLaunchUrl(uri)) {
                                              await launchUrl(uri);
                                            }
                                          } else if (ad.targetEventId != null) {
                                            context.push('/events/${ad.targetEventId}');
                                          }
                                        },
                                      ),
                                    ),
                                    _buildTabs(),
                                    if (extraHeaderWidgets != null) extraHeaderWidgets,
                                  ],
                                ),
                              ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ];
              },
              body: _buildTabContent(),
            ),
            IgnorePointer(
              child: BlocBuilder<ForumCubit, ForumState>(
                buildWhen: (p, c) => p.emojiTrigger != c.emojiTrigger,
                builder: (context, state) {
                  return RepaintBoundary(
                    child: ReactionBackground(
                      emoji: state.selectedEmoji,
                      trigger: state.emojiTrigger,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primaryBackground,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white, size: 32),
        onPressed: () => context.pop(),
      ),
      title: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 8),
          child: SvgPicture.asset(
            'assets/images/official_lynk-x_combined-logo.svg',
            width: 200,
            fit: BoxFit.contain,
          ),
        ),
      ),
      centerTitle: true,
      actions: [
        Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.people_alt, color: Colors.white, size: 32),
            onPressed: () => Scaffold.of(context).openEndDrawer(),
          ),
        ),
      ],
    );
  }

  Widget _buildTabs() {
    return BlocBuilder<FeatureFlagCubit, FeatureFlagState>(
      builder: (context, _) {
        final featureFlags = context.read<FeatureFlagCubit>();
        final showUpdates =
            featureFlags.isEnabled('enable_forum_announcements');
        final showChat = featureFlags.isEnabled('enable_forum_live_chat');
        final showMedia = featureFlags.isEnabled('enable_forum_media');

        return BlocBuilder<ForumCubit, ForumState>(
          buildWhen: (previous, current) =>
              previous.currentTabIndex != current.currentTabIndex,
          builder: (context, state) {
            final updatesSearchQuery = context.select((ForumUpdatesCubit c) => c.state.searchQuery);
            final updatesCount = context.select((ForumUpdatesCubit c) => c.state.messages.length);
            final chatSearchQuery = context.select((ForumChatCubit c) => c.state.searchQuery);
            final chatCount = context.select((ForumChatCubit c) => c.state.messages.length);
            
            final updatesDisplayCount = updatesSearchQuery.isNotEmpty ? updatesCount : null;
            final chatDisplayCount = chatSearchQuery.isNotEmpty ? chatCount : null;

            int displayedIndex = 0;
            return Container(
              height: 48,
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (showUpdates)
                    _buildTab(
                        'Updates', displayedIndex++, state.currentTabIndex,
                        count: updatesDisplayCount),
                  if (showChat)
                    _buildTab(
                        'Live chat', displayedIndex++, state.currentTabIndex,
                        hasIndicator: true, count: chatDisplayCount),
                  if (showMedia)
                    _buildTab('Media', displayedIndex++, state.currentTabIndex),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTab(String label, int index, int currentIndex,
      {bool hasIndicator = false, int? count}) {
    bool isActive = currentIndex == index;
    // Only show indicator if the tab is not currently active
    bool showIndicator = hasIndicator && !isActive;
    final displayLabel = count != null ? '$label ($count)' : label;

    return GestureDetector(
      onTap: () => _navigateToTab(index),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showIndicator)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(
                  displayLabel,
                  style: AppTypography.inter(
                    fontSize: 16,
                    color: isActive ? Colors.white : Colors.white38,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 3,
              width: 40,
              decoration: BoxDecoration(
                color: isActive ? context.accentColor : Colors.transparent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    return BlocBuilder<FeatureFlagCubit, FeatureFlagState>(
      builder: (context, _) {
        final featureFlags = context.read<FeatureFlagCubit>();
        final showUpdates =
            featureFlags.isEnabled('enable_forum_announcements');
        final showChat = featureFlags.isEnabled('enable_forum_live_chat');
        final showMedia = featureFlags.isEnabled('enable_forum_media');

        return BlocBuilder<ForumCubit, ForumState>(
          buildWhen: (p, c) =>
              p.selectedEmoji != c.selectedEmoji ||
              p.emojiTrigger != c.emojiTrigger,
          builder: (context, state) {
            final mainCubit = context.read<ForumCubit>();
            return PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) => mainCubit.setTabIndex(index),
              children: [
                showUpdates ? UpdatesTab(
                  scrollController: _updatesScrollController,
                  onActionTap: () => _navigateToTab(2),
                  onMediaTap: (url) => _viewMedia(url),
                ) : const SizedBox.shrink(),
                showChat ? LiveChatTab(
                  scrollController: _chatScrollController,
                  selectedEmoji: state.selectedEmoji,
                  emojiTrigger: state.emojiTrigger,
                  onActionTap: () => _navigateToTab(2),
                  onMediaTap: (url) => _viewMedia(url),
                ) : const SizedBox.shrink(),
                showMedia ? MediaTab(
                  onMediaTap: (item) => _viewMedia(item.url),
                ) : const SizedBox.shrink(),
              ],
            );
          },
        );
      },
    );
  }

  void _navigateToTab(int index) {
    context.read<ForumCubit>().setTabIndex(index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _viewMedia(String? url) {
    if (url == null) return;
    MediaViewer.show(context, imageUrl: url);
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.primaryBackground,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return child != oldDelegate.child || height != oldDelegate.height;
  }
}

class _ForumPresenceDrawerWrapper extends StatelessWidget {
  final String forumId;
  const _ForumPresenceDrawerWrapper({required this.forumId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ForumPresenceCubit, ForumPresenceState>(
      builder: (context, presenceState) =>
          BlocBuilder<ForumCubit, ForumState>(
        buildWhen: (p, c) =>
            p.eventProgress != c.eventProgress ||
            p.showAds != c.showAds ||
            p.eventId != c.eventId ||
            p.eventCreatedAt != c.eventCreatedAt ||
            p.isOrganizer != c.isOrganizer,
        builder: (context, state) => PresenceDrawer(
          onlineUsers: presenceState.onlineUsers,
          eventProgress: state.eventProgress,
          isPremium: state.isPremium,
          isOrganizer: state.isOrganizer,
          eventId: state.eventId,
          forumId: forumId,
          eventCreatedAt: state.eventCreatedAt,
        ),
      ),
    );
  }
}
