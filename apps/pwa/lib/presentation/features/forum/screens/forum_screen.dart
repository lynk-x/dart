import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_chat_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_ads_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_ads_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_presence_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_presence_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_state.dart';
import 'package:lynk_x/presentation/features/forum/widgets/ad_carousel.dart';
import 'package:lynk_x/presentation/features/forum/widgets/forum_header.dart';
import 'package:lynk_x/presentation/features/forum/widgets/presence_drawer.dart';
import 'package:lynk_x/presentation/features/forum/widgets/media_viewer.dart';
import 'package:lynk_x/presentation/features/forum/widgets/tabs/updates_tab.dart';
import 'package:lynk_x/presentation/features/forum/widgets/tabs/live_chat_tab.dart';
import 'package:lynk_x/presentation/features/forum/widgets/tabs/media_tab.dart';

class ForumPage extends StatelessWidget {
  /// The forum to display. Provided as a path parameter via `/forum/:id`.
  /// Always non-null — the router guarantees a valid UUID before mounting.
  final String forumId;
  const ForumPage({super.key, required this.forumId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ForumCubit(forumId: forumId)..init(),
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
                create: (context) => ForumAdsCubit(
                  forumId: mainCubit.forumId,
                  userId: mainCubit.userId,
                  isPremium: !state.showAds,
                )..init(),
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
                  channel: mainCubit.channel,
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
  bool _showWelcome = true;

  @override
  void initState() {
    super.initState();
    final initialTab = context.read<ForumCubit>().state.currentTabIndex;
    _pageController = PageController(initialPage: initialTab);
  }

  Widget _buildWelcomeBanner() {
    if (!_showWelcome) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF20F928).withValues(alpha: 0.15), Colors.transparent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF20F928).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFF20F928),
              child: Icon(Icons.celebration, color: Colors.black, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome to the Community!',
                    style: AppTypography.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    'Introduce yourself in the Live Chat or see the latest updates.',
                    style: AppTypography.inter(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white24, size: 18),
              onPressed: () => setState(() => _showWelcome = false),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

  @override
  void dispose() {
    _updatesScrollController.dispose();
    _chatScrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _showActionSheet() {
    final mainCubit = context.read<ForumCubit>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.tertiary.withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: const Border(top: BorderSide(color: Colors.white10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 24,
              children: [
                if (mainCubit.state.isOrganizer) ...[
                  _buildActionItem(
                    mainCubit.state.isReadOnly ? Icons.lock_open : Icons.lock,
                    mainCubit.state.isReadOnly ? 'Unlock' : 'Lock',
                    Colors.orange,
                    onTap: () {
                      Navigator.pop(context);
                      final nextStatus = mainCubit.state.isReadOnly ? 'active' : 'read_only';
                      mainCubit.updateForumStatus(nextStatus);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Forum set to $nextStatus')),
                      );
                    },
                  ),
                ],
                _buildActionItem(
                    Icons.notifications_active, 'Reminder', AppColors.secondary,
                    onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reminder set!')),
                  );
                }),
                _buildActionItem(
                    Icons.workspace_premium, 'Badge', AppColors.primary,
                    isPremium: true),
                _buildActionItem(
                    Icons.face_retouching_natural, 'Filters', Colors.pinkAccent,
                    isPremium: true),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String label, Color iconColor,
      {VoidCallback? onTap, bool isPremium = false}) {
    final state = context.read<ForumCubit>().state;
    final isLocked = isPremium && !state.isPremium;

    return GestureDetector(
      onTap: isLocked
          ? () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Premium feature. Upgrade to unlock!')),
              );
            }
          : (onTap ??
              () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label coming soon!')),
                );
              }),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isLocked
                      ? Colors.white10
                      : iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isLocked ? Colors.white24 : iconColor,
                  size: 28,
                ),
              ),
              if (isLocked)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.secondary,
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.lock, size: 10, color: Colors.black),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.inter(
              fontSize: 10,
              color: isLocked ? Colors.white24 : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  void _openGalleryFromChat(String? imageUrl) {
    final state = context.read<ForumCubit>().state;
    final adsState = context.read<ForumAdsCubit>().state;
    MediaViewer.show(
      context,
      imageUrl: imageUrl,
      interstitialAd: state.isPremium ? null : adsState.interstitialAd,
      onMention: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image referenced in chat!')),
        );
      },
    );
  }

  void _openGalleryFromMedia(ForumMedia mediaItem, ForumMediaCubit mediaCubit) {
    final state = context.read<ForumCubit>().state;
    final adsState = context.read<ForumAdsCubit>().state;
    MediaViewer.show(
      context,
      mediaItem: mediaItem,
      interstitialAd: state.isPremium ? null : adsState.interstitialAd,
      onApprove: (state.isOrganizer && !mediaItem.isApproved)
          ? () => mediaCubit.approveMedia(mediaItem.id)
          : null,
      onMention: () {
        context.read<ForumCubit>().setMentionedMedia(mediaItem);
        _onTabSelected(1);
      },
    );
  }

  void _onTabSelected(int index) {
    context.read<ForumCubit>().setTabIndex(index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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
            // Guard against blocked users
            if (state.waveFromName != null && state.waveFromUserId != null) {
              final isBlocked = context.read<BlockCubit>().isBlocked(state.waveFromUserId!);
              if (!isBlocked) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Text('👋 ', style: TextStyle(fontSize: 24)),
                        Text('${state.waveFromName} waved at you!'),
                      ],
                    ),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.primary,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            }
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: AppColors.primaryBackground,
        endDrawer: BlocBuilder<ForumPresenceCubit, ForumPresenceState>(
          builder: (context, presenceState) =>
              BlocBuilder<ForumCubit, ForumState>(
            buildWhen: (p, c) =>
                p.hasMutedLiveChatsMedia != c.hasMutedLiveChatsMedia ||
                p.eventProgress != c.eventProgress ||
                p.showAds != c.showAds,
            builder: (context, state) => PresenceDrawer(
              onlineUsers: presenceState.onlineUsers,
              eventProgress: state.eventProgress,
              isMuted: state.hasMutedLiveChatsMedia,
              onMuteChanged: (val) => cubit.toggleMuteLiveChatsMedia(val),
              isPremium: state.isPremium,
              showAds: state.showAds,
              onAdsChanged: (val) => cubit.toggleAds(val),
            ),
          ),
        ),
        appBar: _buildAppBar(),
        body: Column(
          children: [
            ForumHeader(
              onSearch: (q) =>
                  context.read<ForumUpdatesCubit>().setSearchQuery(q),
              onSearchToggle: () {
                final updatesCubit = context.read<ForumUpdatesCubit>();
                if (updatesCubit.state.searchQuery.isNotEmpty) {
                  updatesCubit.setSearchQuery('');
                }
              },
            ),
            _buildWelcomeBanner(),
            BlocBuilder<FeatureFlagCubit, FeatureFlagState>(
              builder: (context, _) {
                final showBannerAd = context
                    .read<FeatureFlagCubit>()
                    .isEnabled('enable_banner_ad');
                return BlocBuilder<ForumAdsCubit, ForumAdsState>(
                  builder: (context, adsState) {
                    if (cubit.state.isPremium ||
                        !showBannerAd ||
                        adsState.ads.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return AdCarousel(
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
                    );
                  },
                );
              },
            ),
            _buildTabs(),
            Expanded(child: _buildTabContent()),
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
      title: Image.asset(
        'packages/core/assets/images/lynk-x_combined-logo.png',
        width: 200,
        fit: BoxFit.contain,
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
            int displayedIndex = 0;
            return Container(
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: Colors.white10, width: 1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (showUpdates)
                    _buildTab(
                        'Updates', displayedIndex++, state.currentTabIndex),
                  if (showChat)
                    _buildTab(
                        'Live chat', displayedIndex++, state.currentTabIndex,
                        hasIndicator: true),
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
      {bool hasIndicator = false}) {
    bool isActive = currentIndex == index;
    return GestureDetector(
      onTap: () => _onTabSelected(index),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasIndicator)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                (Text(
                  label,
                  style: AppTypography.inter(
                    fontSize: 16,
                    color: isActive ? Colors.white : Colors.white38,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                )),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 3,
              width: 40,
              decoration: BoxDecoration(
                color: isActive ? Colors.white : Colors.transparent,
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
              p.isOrganizer != c.isOrganizer || p.isMuted != c.isMuted,
          builder: (context, state) {
            final mainCubit = context.read<ForumCubit>();
            return PageView(
              controller: _pageController,
              onPageChanged: (index) => mainCubit.setTabIndex(index),
              children: [
                if (showUpdates)
                  // Tab: Updates
                  BlocBuilder<ForumUpdatesCubit, ForumUpdatesState>(
                    builder: (context, updatesState) {
                      final updatesCubit = context.read<ForumUpdatesCubit>();
                      return UpdatesTab(
                        messages: updatesState.messages,
                        scrollController: _updatesScrollController,
                        isLoading: updatesState.isLoading,
                        onRefresh: () async => updatesCubit.refresh(),
                        onSendMessage: (text, replyTo) => updatesCubit
                            .sendMessage(text, 
                              isOrganizer: state.isOrganizer,
                              isPremium: state.isPremium,
                            ),
                        onPin: (msg) => mainCubit.pinMessage(msg),
                        onMute: (msg) => mainCubit.muteUser(msg.userId),
                        onBan: (msg) => mainCubit.banUser(msg.userId),
                        onReport: _showReportDialog,
                        selectedCategory: updatesState.selectedCategory,
                        onSelectionChanged: updatesCubit.setCategory,
                        isOrganizer: state.isOrganizer,
                        onActionTap: _showActionSheet,
                        mentionedMedia: updatesState.mentionedMedia,
                        onCancelMention: () =>
                            updatesCubit.setMentionedMedia(null),
                        members: state.members,
                        linkPreviews: updatesState.linkPreviews,
                        onLinkPreviewDataFetched: updatesCubit.saveLinkPreview,
                      );
                    },
                  ),
                if (showChat)
                  // Tab: Live Chat
                  LiveChatTab(
                    scrollController: _chatScrollController,
                    onReport: _showReportDialog,
                    selectedEmoji: state.selectedEmoji,
                    emojiTrigger: state.emojiTrigger,
                    onActionTap: _showActionSheet,
                    onPin: (msg) => mainCubit.pinMessage(msg),
                    onMute: (msg) => mainCubit.muteUser(msg.userId),
                    onBan: (msg) => mainCubit.banUser(msg.userId),
                    isOrganizer: state.isOrganizer,
                    isMuted: state.isMuted || state.isReadOnly,
                    members: state.members,
                    onMediaTap: _openGalleryFromChat,
                  ),
                if (showMedia)
                  // Tab: Media
                  BlocProvider(
                    create: (context) => ForumMediaCubit(
                      forumId: mainCubit.forumId,
                      userId: mainCubit.userId,
                      isOrganizer: state.isOrganizer,
                    )..init(),
                    child: BlocBuilder<ForumMediaCubit, ForumMediaState>(
                      builder: (context, mediaState) {
                        final mediaCubit = context.read<ForumMediaCubit>();
                        return MediaTab(
                          onRefresh: () async => mediaCubit.refreshMedia(),
                          onScrollToBottom: () => mediaCubit.loadMore(),
                          onMediaTap: (media) =>
                              _openGalleryFromMedia(media, mediaCubit),
                          mediaItems: mediaState.mediaItems,
                          isLoading: mediaState.isLoading,
                          onUpload: (file, type, mimeType) =>
                              mediaCubit.uploadMedia(
                            file: file,
                            type: type,
                            mimeType: mimeType,
                          ),
                          isMuted: state.isMuted || state.isReadOnly,
                          isUploading: mediaState.isUploading,
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _showReportDialog(ChatMessage message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.tertiary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Report Message',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Why are you reporting this message?',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            ...['Spam', 'Inappropriate', 'Harassment', 'Other'].map((reason) {
              return ListTile(
                title:
                    Text(reason, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  context.read<ForumCubit>().reportUser(
                        message.userId,
                        reason,
                        messageId: message.id,
                      );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Reported for $reason')),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}
