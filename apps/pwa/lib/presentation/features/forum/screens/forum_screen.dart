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
import 'package:lynk_x/presentation/features/forum/widgets/reaction_bar.dart';
import 'package:lynk_x/presentation/features/forum/widgets/polls/poll_card_editor.dart';

import 'package:lynk_x/presentation/features/forum/widgets/welcome_banner.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

class ForumPage extends StatelessWidget {
  /// The forum to display. Provided as a path parameter via `/forum/:reference`.
  /// Always non-null — the router guarantees a valid slug before mounting.
  final String forumReference;
  const ForumPage({super.key, required this.forumReference});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ForumCubit(
        repo: forumRepository,
        forumReference: forumReference,
      )..init(),
      child: BlocBuilder<ForumCubit, ForumState>(
        builder: (context, state) {
          final fId = state.forumId;
          if (fId == null) {
            return Builder(
              builder: (context) => Scaffold(
                backgroundColor: AppColors.primaryBackground,
                body: Center(
                  child: CircularProgressIndicator(color: context.accentColor),
                ),
              ),
            );
          }
          final mainCubit = context.read<ForumCubit>();
          return MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (context) {
                  final ads = ForumAdsCubit(
                    forumId: fId,
                    userId: mainCubit.userId,
                    isPremium: !state.showAds,
                    eventId: state.eventId,
                    eventCreatedAt: state.eventCreatedAt,
                  );
                  if (context
                      .read<FeatureFlagCubit>()
                      .isEnabled('enable_forum_ads')) {
                    ads.init();
                  }
                  return ads;
                },
              ),
              BlocProvider(
                create: (context) {
                  final cubit = ForumPresenceCubit(
                    forumId: fId,
                    userId: mainCubit.userId,
                    userName: mainCubit.userName,
                    isOrganizer: state.isOrganizer,
                    isPremium: state.isPremium,
                  );
                  final flagEnabled = context
                      .read<FeatureFlagCubit>()
                      .isEnabled('enable_realtime_presence');
                  if (flagEnabled) {
                    cubit.init();
                  }
                  return cubit;
                },
              ),
              BlocProvider(
                create: (context) {
                  final cubit = ForumUpdatesCubit(
                    forumId: fId,
                    userId: mainCubit.userId,
                    userName: mainCubit.userName,
                  )..init();
                  cubit.syncForumContext(
                    forumCreatedAt: state.forumCreatedAt,
                    channelId: state.channelId,
                    channelCreatedAt: state.channelCreatedAt,
                  );
                  return cubit;
                },
              ),
              BlocProvider(
                create: (context) {
                  final cubit = ForumChatCubit(
                    forumId: fId,
                    userId: mainCubit.userId,
                    userName: mainCubit.userName,
                    repo: forumRepository,
                  )..init();
                  cubit.syncForumContext(
                    forumCreatedAt: state.forumCreatedAt,
                    channelId: state.channelId,
                    channelCreatedAt: state.channelCreatedAt,
                  );
                  return cubit;
                },
              ),
              BlocProvider(
                create: (context) => ForumMediaCubit(
                  forumId: fId,
                  userId: mainCubit.userId,
                  isOrganizer: state.isOrganizer,
                  isModerator: state.isModerator,
                  repo: forumRepository,
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

  bool _isMediaTabActive() {
    final featureFlags = context.read<FeatureFlagCubit>();
    final showUpdates = featureFlags.isEnabled('enable_forum_announcements');
    final showChat = featureFlags.isEnabled('enable_forum_live_chat');
    final showMedia = featureFlags.isEnabled('enable_forum_media');

    if (!showMedia) return false;

    final mediaIndex = (showUpdates ? 1 : 0) + (showChat ? 1 : 0);
    final currentTabIndex = context.read<ForumCubit>().state.currentTabIndex;
    return currentTabIndex == mediaIndex;
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
            if (!context
                .read<FeatureFlagCubit>()
                .isEnabled('enable_social_actions')) {
              return;
            }
            if (state.waveFromName != null && state.waveFromUserId != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Text('👋 ', style: TextStyle(fontSize: 24)),
                      Text(
                        '${state.waveFromName} waved at you!',
                        style: const TextStyle(color: Colors.black),
                      ),
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
        BlocListener<ForumCubit, ForumState>(
          listenWhen: (p, c) => p.currentTabIndex != c.currentTabIndex,
          listener: (context, state) {
            if (_isMediaTabActive()) {
              final mediaState = context.read<ForumMediaCubit>().state;
              _precacheMedia(mediaState.mediaItems);
            }
          },
        ),
        BlocListener<ForumMediaCubit, ForumMediaState>(
          listenWhen: (p, c) => p.mediaItems != c.mediaItems,
          listener: (context, state) {
            if (_isMediaTabActive()) {
              _precacheMedia(state.mediaItems);
            }
          },
        ),
        BlocListener<ForumCubit, ForumState>(
          listenWhen: (p, c) =>
              p.forumCreatedAt != c.forumCreatedAt ||
              p.accountId != c.accountId ||
              p.channelId != c.channelId ||
              p.channelCreatedAt != c.channelCreatedAt,
          listener: (context, state) {
            context.read<ForumUpdatesCubit>().syncForumContext(
                  forumCreatedAt: state.forumCreatedAt,
                  channelId: state.channelId,
                  channelCreatedAt: state.channelCreatedAt,
                );
            context.read<ForumChatCubit>().syncForumContext(
                  forumCreatedAt: state.forumCreatedAt,
                  channelId: state.channelId,
                  channelCreatedAt: state.channelCreatedAt,
                );
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
        endDrawer: _ForumPresenceDrawerWrapper(
          forumId: cubit.forumId ?? '',
          onEventProgressTap: () {
            final state = cubit.state;
            if (state.forumId == null || state.forumId!.isEmpty) {
              AppSnackBars.showInfo(context, 'No forum found.');
              return;
            }
            Navigator.of(context).pop();
            context.push(
              '/forum/${cubit.forumReference}/sessions?forumId=${state.forumId}&createdAt=${state.forumCreatedAt?.toIso8601String()}',
              extra: {
                'isOrganizer': state.isOrganizer,
              },
            );
          },
        ),
        appBar: _buildAppBar(),
        body: Stack(
          children: [
            if (_showWelcome)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
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
            NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  BlocBuilder<ForumCubit, ForumState>(
                    buildWhen: (p, c) =>
                        p.isPremium != c.isPremium ||
                        p.showAds != c.showAds ||
                        p.currentTabIndex != c.currentTabIndex,
                    builder: (context, forumState) {
                      return BlocBuilder<ForumAdsCubit, ForumAdsState>(
                        builder: (context, adsState) {
                          final showBannerAd = context
                              .read<FeatureFlagCubit>()
                              .isEnabled('enable_banner_ad');
                          final hasAds = !forumState.isPremium &&
                              showBannerAd &&
                              context
                                  .read<FeatureFlagCubit>()
                                  .isEnabled('enable_forum_ads') &&
                              adsState.ads.isNotEmpty;

                          final adsHeight = hasAds ? 50.0 : 0.0;

                          double extraHeight = 0;
                          Widget? extraHeaderWidgets;

                          final featureFlags = context.read<FeatureFlagCubit>();
                          final showUpdates = featureFlags
                              .isEnabled('enable_forum_announcements');
                          final showChat =
                              featureFlags.isEnabled('enable_forum_live_chat');
                          final chatTabIndex = showUpdates ? 1 : 0;

                          if (forumState.currentTabIndex == 0 && showUpdates) {
                            final updatesCubit =
                                context.read<ForumUpdatesCubit>();
                            final selectedCategory =
                                context.select<ForumUpdatesCubit, String?>(
                              (c) => c.state.selectedCategory,
                            );
                            final pinnedMessage =
                                context.select<ForumUpdatesCubit, ChatMessage?>(
                              (c) {
                                for (final m in c.state.messages) {
                                  if (m.isPinned) return m;
                                }
                                return null;
                              },
                            );

                            extraHeight += 52.0; // CategoryFilterBar
                            if (pinnedMessage != null) {
                              extraHeight +=
                                  48.0; // InfoBanner exact calculated height for 2 lines
                            }

                            extraHeaderWidgets = Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ColoredBox(
                                  color: AppColors.primaryBackground,
                                  child: CategoryFilterBar(
                                    selectedCategory: selectedCategory,
                                    onSelectionChanged: (cat) =>
                                        updatesCubit.setCategory(cat),
                                  ),
                                ),
                                if (pinnedMessage != null)
                                  Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(4, 4, 4, 4),
                                    child: InfoBanner(
                                      icon: Icons.push_pin,
                                      text: pinnedMessage.message.length > 80
                                          ? '${pinnedMessage.message.substring(0, 80)}…'
                                          : pinnedMessage.message,
                                    ),
                                  ),
                              ],
                            );
                          } else if (forumState.currentTabIndex ==
                                  chatTabIndex &&
                              showChat) {
                            extraHeight +=
                                44.0; // ReactionBar height + vertical padding
                            extraHeaderWidgets = ColoredBox(
                              color: AppColors.primaryBackground,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: ReactionBar(
                                  onEmojiTap: (emoji) => context
                                      .read<ForumCubit>()
                                      .handleEmojiTap(emoji),
                                ),
                              ),
                            );
                          }

                          final totalHeaderHeight =
                              104.0 + adsHeight + extraHeight;
                          return SliverOverlapAbsorber(
                            handle:
                                NestedScrollView.sliverOverlapAbsorberHandleFor(
                                    context),
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
                                          final nextStatus =
                                              forumState.isReadOnly
                                                  ? 'open'
                                                  : 'read_only';
                                          cubit.updateForumStatus(nextStatus);
                                          AppSnackBars.showInfo(
                                            context,
                                            forumState.isReadOnly
                                                ? 'Chat unlocked'
                                                : 'Chat locked',
                                          );
                                        },
                                        onSearch: (q) {
                                          context
                                              .read<ForumUpdatesCubit>()
                                              .setSearchQuery(q);
                                          context
                                              .read<ForumChatCubit>()
                                              .setSearchQuery(q);
                                        },
                                        onSearchToggle: () {
                                          final updatesCubit =
                                              context.read<ForumUpdatesCubit>();
                                          final chatCubit =
                                              context.read<ForumChatCubit>();
                                          if (updatesCubit.state.searchQuery
                                                  .isNotEmpty ||
                                              chatCubit.state.searchQuery
                                                  .isNotEmpty) {
                                            updatesCubit.setSearchQuery('');
                                            chatCubit.setSearchQuery('');
                                          }
                                        },
                                      ),
                                      if (hasAds)
                                        RepaintBoundary(
                                          child: AdCarousel(
                                            ads: adsState.ads,
                                            onAdViewed: (adId) => context
                                                .read<ForumAdsCubit>()
                                                .logAdImpression(adId),
                                            onAdClicked: (ad) async {
                                              context
                                                  .read<ForumAdsCubit>()
                                                  .logAdClick(ad.id);
                                              if (ad.targetUrl != null) {
                                                final uri =
                                                    Uri.parse(ad.targetUrl!);
                                                if (await canLaunchUrl(uri)) {
                                                  await launchUrl(uri);
                                                }
                                              } else if (ad.targetEventId !=
                                                  null) {
                                                context.push(
                                                    '/events/${ad.targetEventId}');
                                              }
                                            },
                                          ),
                                        ),
                                      _buildTabs(),
                                      if (extraHeaderWidgets != null)
                                        extraHeaderWidgets,
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
        onPressed: () => context.go('/'),
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
            final updatesSearchQuery =
                context.select((ForumUpdatesCubit c) => c.state.searchQuery);
            final updatesCount = context
                .select((ForumUpdatesCubit c) => c.state.messages.length);
            final chatSearchQuery =
                context.select((ForumChatCubit c) => c.state.searchQuery);
            final chatCount =
                context.select((ForumChatCubit c) => c.state.messages.length);

            final updatesDisplayCount =
                updatesSearchQuery.isNotEmpty ? updatesCount : null;
            final chatDisplayCount =
                chatSearchQuery.isNotEmpty ? chatCount : null;

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
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
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
                showUpdates
                    ? UpdatesTab(
                        scrollController: _updatesScrollController,
                        onActionTap: () => _navigateToTab(2),
                        onMediaTap: (url) => _viewMedia(url),
                        onCreatePollOrQuiz: () =>
                            _showCreatePollOrQuizSheet(isLiveChat: false),
                      )
                    : const SizedBox.shrink(),
                showChat
                    ? LiveChatTab(
                        scrollController: _chatScrollController,
                        selectedEmoji: state.selectedEmoji,
                        emojiTrigger: state.emojiTrigger,
                        onActionTap: () => _navigateToTab(2),
                        onMediaTap: (url) => _viewMedia(url),
                        onCreatePollOrQuiz: () =>
                            _showCreatePollOrQuizSheet(isLiveChat: true),
                      )
                    : const SizedBox.shrink(),
                showMedia
                    ? MediaTab(
                        onMediaTap: (item) => _viewForumMedia(item),
                      )
                    : const SizedBox.shrink(),
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

  void _showCreatePollOrQuizSheet({required bool isLiveChat}) {
    final forumId = context.read<ForumCubit>().state.forumId;
    final forumReference = context.read<ForumCubit>().forumReference;
    final isOrganizer = context.read<ForumCubit>().state.isOrganizer;
    if (forumId == null || !isOrganizer) return;

    final channelId = isLiveChat
        ? context.read<ForumChatCubit>().channelId
        : context.read<ForumUpdatesCubit>().channelId;
    final channelCreatedAt = (isLiveChat
            ? context.read<ForumChatCubit>().channelCreatedAt
            : context.read<ForumUpdatesCubit>().channelCreatedAt)
        ?.toIso8601String();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add to Forum',
                      style: AppTypography.interTight(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _CreateOptionCard(
                icon: Icons.poll_outlined,
                accentColor: const Color(
                    0xFF3B82F6), // blue — distinct from the poll card's own green
                title: 'Create Poll',
                description:
                    'Ask a quick question and watch results come in live.',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showPollEditorSheet(
                    forumId: forumId,
                    channelId: channelId,
                    channelCreatedAt: channelCreatedAt,
                    messageType: isLiveChat ? 'livechat_poll' : 'update_poll',
                  );
                },
              ),
              const SizedBox(height: 12),
              _CreateOptionCard(
                icon: Icons.quiz_outlined,
                accentColor: const Color(
                    0xFFFF8A3D), // amber — distinct from subscription gold
                title: 'Create Quiz',
                description:
                    'Run a timed, scored quiz with a live leaderboard.',
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push(
                    '/forum/$forumReference/quiz/create',
                    extra: {
                      'forumId': forumId,
                      'isOrganizer': true,
                      'isLiveChat': isLiveChat,
                      'channelId': channelId,
                      'channelCreatedAt': channelCreatedAt,
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPollEditorSheet({
    required String forumId,
    String? channelId,
    String? channelCreatedAt,
    required String messageType,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          top: 16,
        ),
        child: PollCardEditor(
          forumId: forumId,
          channelId: channelId,
          channelCreatedAt: channelCreatedAt,
          messageType: messageType,
          onCancel: () => Navigator.pop(sheetContext),
          onPublished: () => Navigator.pop(sheetContext),
        ),
      ),
    );
  }

  void _viewMedia(String? url) {
    if (url == null) return;
    MediaViewer.show(context, imageUrl: url);
  }

  void _viewForumMedia(ForumMedia item) {
    final mediaCubit = context.read<ForumMediaCubit>();
    final forumCubit = context.read<ForumCubit>();
    final isAuthorized =
        forumCubit.state.isOrganizer || forumCubit.state.isModerator;
    final isUploader = item.uploaderId == forumCubit.userId;

    MediaViewer.show(
      context,
      imageUrl: item.url,
      mediaItem: item,
      onApprove: (isAuthorized && !item.isApproved)
          ? () => mediaCubit.approveMedia(item)
          : null,
      onReject: (isAuthorized || isUploader)
          ? () => mediaCubit.deleteMedia(item)
          : null,
    );
  }
}

/// A large tappable card for the "Add to Forum" sheet — used for both
/// Create Poll and Create Quiz, differentiated by [accentColor] so each
/// previews the visual identity of what it creates without reusing the
/// poll card's own green or the subscription screen's gold.
class _CreateOptionCard extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _CreateOptionCard({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: accentColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: AppTypography.interTight(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'NEW',
                            style: AppTypography.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: AppTypography.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
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
  final VoidCallback onEventProgressTap;
  const _ForumPresenceDrawerWrapper({
    required this.forumId,
    required this.onEventProgressTap,
  });

  @override
  Widget build(BuildContext context) {
    final presenceState = context.watch<ForumPresenceCubit>().state;
    final forumState = context.watch<ForumCubit>().state;

    return PresenceDrawer(
      members: forumState.members,
      onlineUsers: presenceState.onlineUsers,
      eventProgress: forumState.eventProgress,
      isPremium: forumState.isPremium,
      isOrganizer: forumState.isOrganizer,
      eventId: forumState.eventId,
      forumId: forumId,
      isLoading: presenceState.isLoading,
      eventCreatedAt: forumState.eventCreatedAt,
      onEventProgressTap: onEventProgressTap,
    );
  }
}
