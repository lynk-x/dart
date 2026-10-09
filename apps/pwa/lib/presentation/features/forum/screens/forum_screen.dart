import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lynk_x/presentation/features/forum/widgets/info_banner.dart';
import 'package:lynk_x/presentation/features/forum/widgets/category_filter_bar.dart';
import 'package:lynk_x/presentation/features/forum/widgets/skeletons.dart';
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
import 'package:lynk_x/presentation/features/forum/models/call_participant.dart';
import 'package:lynk_x/presentation/features/forum/widgets/ad_carousel.dart';
import 'package:lynk_x/presentation/features/forum/widgets/header.dart';
import 'package:lynk_x/presentation/features/forum/widgets/stream_stage.dart';
import 'package:lynk_x/presentation/features/forum/widgets/speaker_invite_dialog.dart';
import 'package:lynk_x/presentation/features/forum/widgets/mini_overlay.dart';
import 'package:lynk_x/presentation/features/forum/services/stream_service.dart';
import 'package:lynk_x/presentation/features/forum/services/mini_overlay_service.dart';
import 'package:lynk_x/presentation/features/forum/services/call_sound_service.dart';
import 'package:lynk_x/presentation/features/forum/widgets/presence_drawer.dart';
import 'package:lynk_x/presentation/features/forum/widgets/media_viewer.dart';
import 'package:lynk_x/presentation/features/forum/widgets/tabs/updates_tab.dart';
import 'package:lynk_x/presentation/features/forum/widgets/tabs/live_chat_tab.dart';
import 'package:lynk_x/presentation/features/forum/widgets/tabs/media_tab.dart';
import 'package:lynk_x/presentation/features/forum/widgets/reaction_background.dart';
import 'package:lynk_x/presentation/features/forum/widgets/reaction_bar.dart';
import 'package:lynk_x/presentation/features/forum/widgets/polls/poll_card_editor.dart';
import 'package:lynk_x/presentation/features/forum/widgets/tab_bar.dart';
import 'package:lynk_x/presentation/features/forum/widgets/action_sheets.dart';

import 'package:lynk_x/presentation/shared/utils/permission_acks.dart';

import 'package:lynk_x/presentation/features/forum/cubit/forum_audio_stream_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_audio_stream_state.dart';
import 'package:lynk_x/presentation/features/forum/services/forum_audio_stream_service.dart'
    show AudioCallTelemetry;
import 'package:lynk_x/presentation/features/forum/widgets/welcome_banner.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import 'package:lynk_x/presentation/features/forum/widgets/bloc_providers.dart';
import 'package:lynk_x/presentation/features/forum/core/forum_config.dart';

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
            return SkeletonFadeSingleMount(
              child: Scaffold(
                key: const ValueKey('loading'),
                backgroundColor: AppColors.primaryBackground,
                body: Center(
                  child: CircularProgressIndicator(color: context.accentColor),
                ),
              ),
            );
          }
          final mainCubit = context.read<ForumCubit>();
          return SkeletonFadeSingleMount(
            child: ForumBlocProviders(
              forumId: fId,
              mainCubit: mainCubit,
              state: state,
              child: const ForumView(),
            ),
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

    ForumVideoStreamService()
        .pendingVideoInviteFromHostName
        .addListener(_onVideoInviteChanged);
  }

  void _onVideoInviteChanged() {
    final fromHostName =
        ForumVideoStreamService().pendingVideoInviteFromHostName.value;
    if (fromHostName == null || !mounted) return;
    showVideoSpeakerInviteDialog(context, fromHostName);
  }

  void _precacheMedia(List<ForumMedia> mediaItems) {
    if (!mounted) return;
    // Pre-cache only the first 9 items to save bandwidth but ensure instant grid load
    final itemsToPrecache = mediaItems.take(9);
    for (final item in itemsToPrecache) {
      final url = item.thumbnailUrl ?? item.url;
      if (url.isNotEmpty && !_precachedUrls.contains(url)) {
        if (_precachedUrls.length >= ForumConfig.maxPrecachedMediaUrls) {
          _precachedUrls.remove(_precachedUrls.first);
        }
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

    final mediaIndex = ForumConfig.mediaTabIndex(
      showUpdates: showUpdates,
      showChat: showChat,
    );
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
    ForumVideoStreamService()
        .pendingVideoInviteFromHostName
        .removeListener(_onVideoInviteChanged);
    _precachedUrls.clear();
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
            context.read<ForumMediaCubit>().syncForumContext(
                  forumCreatedAt: state.forumCreatedAt,
                );
          },
        ),
        BlocListener<ForumCubit, ForumState>(
          listenWhen: (p, c) => p.userName != c.userName,
          listener: (context, state) {
            context.read<ForumPresenceCubit>().updateUserName(state.userName);
            context.read<ForumChatCubit>().updateUserName(state.userName);
            context.read<ForumUpdatesCubit>().updateUserName(state.userName);
            context
                .read<ForumAudioStreamCubit>()
                .updateUserName(state.userName);
          },
        ),
        BlocListener<ForumAudioStreamCubit, ForumAudioStreamState>(
          listenWhen: (p, c) => c.errorMessage != null,
          listener: (context, state) {
            AppSnackBars.showError(context, state.errorMessage!);
            context.read<ForumAudioStreamCubit>().clearAudioStreamError();
          },
        ),
        BlocListener<ForumAudioStreamCubit, ForumAudioStreamState>(
          listenWhen: (p, c) => c.infoMessage != null,
          listener: (context, state) {
            AppSnackBars.showInfo(context, state.infoMessage!);
          },
        ),
        BlocListener<ForumAudioStreamCubit, ForumAudioStreamState>(
          listenWhen: (p, c) =>
              p.pendingInviteFromHostName == null &&
              c.pendingInviteFromHostName != null,
          listener: (context, state) {
            showSpeakerInviteDialog(context, state.pendingInviteFromHostName!);
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
            ValueListenableBuilder<bool>(
              valueListenable: ForumVideoStreamService().isLiveNotifier,
              builder: (context, isLive, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable:
                      ForumVideoStreamService().isMinimizedNotifier,
                  builder: (context, isMinimized, _) {
                    final isStageActive = isLive && !isMinimized;

                    return NestedScrollView(
                      headerSliverBuilder: (context, innerBoxIsScrolled) {
                        return [
                          BlocBuilder<ForumCubit, ForumState>(
                            buildWhen: (p, c) =>
                                p.isPremium != c.isPremium ||
                                p.showAds != c.showAds ||
                                p.currentTabIndex != c.currentTabIndex ||
                                p.forumStatus != c.forumStatus,
                            builder: (context, forumState) {
                              return BlocBuilder<ForumAdsCubit, ForumAdsState>(
                                builder: (context, adsState) {
                                  final hasAds = ForumConfig.showBannerAd(
                                    isPremium: forumState.isPremium,
                                    bannerEnabled: context
                                        .read<FeatureFlagCubit>()
                                        .isEnabled('enable_banner_ad'),
                                    forumAdsEnabled: context
                                        .read<FeatureFlagCubit>()
                                        .isEnabled('enable_forum_ads'),
                                    hasAdsContent: adsState.ads.isNotEmpty,
                                  );

                                  final adsHeight = hasAds ? 50.0 : 0.0;

                                  // Updates is always tab 0 when enabled
                                  // (PageView's fixed children order) — used
                                  // to gate the header's start-call/
                                  // start-stream gestures to that tab only.
                                  final showUpdates = context
                                      .read<FeatureFlagCubit>()
                                      .isEnabled('enable_forum_announcements');
                                  final isUpdatesTabActive = showUpdates &&
                                      forumState.currentTabIndex == 0;

                                  double extraHeight = 0;
                                  Widget? extraHeaderWidgets;

                                  if (!isStageActive) {
                                    final featureFlags =
                                        context.read<FeatureFlagCubit>();
                                    final showChat = featureFlags
                                        .isEnabled('enable_forum_live_chat');
                                    final chatTabIndex = showUpdates ? 1 : 0;

                                    if (forumState.currentTabIndex == 0 &&
                                        showUpdates) {
                                      final updatesCubit =
                                          context.read<ForumUpdatesCubit>();
                                      final selectedCategory = context
                                          .select<ForumUpdatesCubit, String?>(
                                        (c) => c.state.selectedCategory,
                                      );
                                      final pinnedMessage = context.select<
                                          ForumUpdatesCubit, ChatMessage?>(
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
                                              selectedCategory:
                                                  selectedCategory,
                                              onSelectionChanged: (cat) =>
                                                  updatesCubit.setCategory(cat),
                                            ),
                                          ),
                                          if (pinnedMessage != null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      4, 4, 4, 4),
                                              child: InfoBanner(
                                                icon: Icons.push_pin,
                                                text: pinnedMessage
                                                            .message.length >
                                                        80
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
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8.0),
                                          child: ReactionBar(
                                            onEmojiTap: (emoji) => context
                                                .read<ForumCubit>()
                                                .handleEmojiTap(emoji),
                                          ),
                                        ),
                                      );
                                    }
                                  }

                                  final forumHeaderHeight = 56.0;
                                  final totalHeaderHeight = (isStageActive
                                          ? forumHeaderHeight
                                          : 104.0) +
                                      adsHeight +
                                      (isStageActive ? 0 : extraHeight);
                                  return SliverOverlapAbsorber(
                                    handle: NestedScrollView
                                        .sliverOverlapAbsorberHandleFor(
                                            context),
                                    sliver: SliverPersistentHeader(
                                      pinned: true,
                                      delegate: _SliverAppBarDelegate(
                                        height: totalHeaderHeight,
                                        child: SizedBox(
                                          height: totalHeaderHeight,
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            children: [
                                              BlocBuilder<ForumAudioStreamCubit,
                                                  ForumAudioStreamState>(
                                                builder: (context, audioState) {
                                                  final audioCubit = context.read<
                                                      ForumAudioStreamCubit>();
                                                  final videoService =
                                                      ForumVideoStreamService();
                                                  return ValueListenableBuilder<
                                                      AudioCallTelemetry>(
                                                    valueListenable: audioCubit
                                                        .service
                                                        .listenerTelemetryNotifier,
                                                    builder: (context,
                                                        audioTelemetry, _) {
                                                      return ForumHeader(
                                                        isVideoStreamLive:
                                                            isLive,
                                                        isAudioLive:
                                                            audioState.isLive,
                                                        isWeakConnection: !isLive &&
                                                            audioState.isLive &&
                                                            audioState.role !=
                                                                ForumHeaderRole
                                                                    .host &&
                                                            audioTelemetry
                                                                .isPoorConnection,
                                                        isReconnecting: !isLive &&
                                                            audioState.isLive &&
                                                            (audioState
                                                                    .isReconnecting ||
                                                                audioState
                                                                    .isListenerReconnecting),
                                                        role: isLive &&
                                                                forumState
                                                                    .isOrganizer
                                                            ? ForumHeaderRole
                                                                .host
                                                            : audioState.role,
                                                        activeSpeakerNames:
                                                            audioState
                                                                .activeSpeakerNames,
                                                        currentUserName: cubit
                                                            .state.userName,
                                                        isMicMuted: isLive
                                                            ? videoService
                                                                .isMicMuted
                                                            : audioState
                                                                .isMicMuted,
                                                        isCameraOn: videoService
                                                            .isCameraOn,
                                                        isBroadcastMuted:
                                                            audioState
                                                                .isBroadcastMuted,
                                                        getAudioLevel: () => isLive
                                                            ? videoService
                                                                .getAudioLevel()
                                                            : audioCubit.service
                                                                .getAudioLevel(),
                                                        onToggleMic: () {
                                                          if (isLive) {
                                                            final nextMicMuted =
                                                                !videoService
                                                                    .isMicMuted;
                                                            videoService
                                                                    .isMicMuted =
                                                                nextMicMuted;
                                                            videoService.toggleMic(
                                                                !nextMicMuted);
                                                            videoService
                                                                .updateParticipantMediaState(
                                                                    'host',
                                                                    isMicMuted:
                                                                        nextMicMuted);
                                                            if (mounted) {
                                                              setState(() {});
                                                            }
                                                          } else {
                                                            if (audioState
                                                                .isMicMuted) {
                                                              PermissionAcks
                                                                  .ensureAcknowledged(
                                                                context,
                                                                PermissionAckType
                                                                    .microphone,
                                                                title:
                                                                    'Microphone Permission',
                                                                description:
                                                                    'To speak in live community streams, Lynk-X needs access to your microphone.',
                                                                icon: Icons
                                                                    .mic_rounded,
                                                                actionLabel:
                                                                    'Allow Microphone',
                                                                onReady: () =>
                                                                    audioCubit
                                                                        .toggleMic(),
                                                              );
                                                            } else {
                                                              audioCubit
                                                                  .toggleMic();
                                                            }
                                                          }
                                                        },
                                                        onToggleCamera: () {
                                                          if (isLive) {
                                                            final nextCamOn =
                                                                !videoService
                                                                    .isCameraOn;
                                                            videoService
                                                                    .isCameraOn =
                                                                nextCamOn;
                                                            videoService
                                                                .toggleCamera(
                                                                    nextCamOn);
                                                            videoService
                                                                .updateParticipantMediaState(
                                                                    'host',
                                                                    isCameraOn:
                                                                        nextCamOn);
                                                            if (mounted) {
                                                              setState(() {});
                                                            }
                                                          }
                                                        },
                                                        onToggleBroadcastMute:
                                                            () => audioCubit
                                                                .toggleBroadcastMute(),
                                                        onEndBroadcast: () {
                                                          final name = forumState
                                                                  .userName
                                                                  .isNotEmpty
                                                              ? forumState
                                                                  .userName
                                                              : 'Host';
                                                          // Read cubits before any awaited work below —
                                                          // context shouldn't cross an async gap.
                                                          final chatCubit =
                                                              context.read<
                                                                  ForumChatCubit>();
                                                          final updatesCubit =
                                                              context.read<
                                                                  ForumUpdatesCubit>();
                                                          AppSnackBars.showInfo(
                                                              context,
                                                              'You ended the call.');

                                                          if (isLive) {
                                                            final videoService =
                                                                ForumVideoStreamService();
                                                            final vfId =
                                                                forumState
                                                                    .forumId;
                                                            videoService
                                                                .setMinimized(
                                                                    false);
                                                            videoService
                                                                .stopVideoStream();
                                                            videoService
                                                                .setLive(false);
                                                            videoService
                                                                .hostSessionIdNotifier
                                                                .value = null;
                                                            MiniOverlayService()
                                                                .endPipSession();
                                                            // Host is the only
                                                            // party that can
                                                            // reach this branch
                                                            // (only isHost sees
                                                            // the end-broadcast
                                                            // control) — safe to
                                                            // fire-and-forget,
                                                            // local teardown above
                                                            // already happened.
                                                            if (vfId != null &&
                                                                vfId.isNotEmpty) {
                                                              unawaited(
                                                                  videoService
                                                                      .updateForumStreamingConfig(
                                                                forumId: vfId,
                                                                isLive: false,
                                                              )
                                                                      .catchError(
                                                                          (e) {
                                                                debugPrint(
                                                                    '[ForumScreen] video end updateForumStreamingConfig failed: $e');
                                                              }));
                                                            }
                                                            final vfSummaryId =
                                                                videoService
                                                                    .callSummaryId;
                                                            videoService
                                                                    .callSummaryId =
                                                                null;
                                                            unawaited(videoService
                                                                .endCallSummary(
                                                                    vfSummaryId));
                                                            // Tells every already-joined listener/co-host
                                                            // the call ended (server already force-closed
                                                            // their forum_call_participants row).
                                                            unawaited(videoService
                                                                .broadcastVideoEvent(
                                                                    action:
                                                                        'end_stream'));
                                                            unawaited(
                                                                CallSoundService
                                                                    .playEnd());

                                                            // Mirrors the "started the live stream"
                                                            // announcement posted on start — without
                                                            // this, isLiveSessionEvent's "ended" text
                                                            // check (updates_tab.dart) never has
                                                            // anything to match, and the JoinCard
                                                            // session-id comparison fix only covers
                                                            // widgets that were mounted to witness the
                                                            // live transition themselves.
                                                            chatCubit
                                                                .sendMessage(
                                                              '$name ended the live stream',
                                                              isOrganizer:
                                                                  forumState
                                                                      .isOrganizer,
                                                              isPremium:
                                                                  forumState
                                                                      .isPremium,
                                                              messageType:
                                                                  MessageType
                                                                      .systemChat,
                                                            );
                                                            updatesCubit
                                                                .sendMessage(
                                                              '$name ended the live stream',
                                                              isOrganizer:
                                                                  forumState
                                                                      .isOrganizer,
                                                              isPremium:
                                                                  forumState
                                                                      .isPremium,
                                                              messageType:
                                                                  MessageType
                                                                      .systemAnnouncement,
                                                            );
                                                          } else {
                                                            audioCubit
                                                                .endAudioStream();

                                                            chatCubit
                                                                .sendMessage(
                                                              '$name ended the live call',
                                                              isOrganizer:
                                                                  forumState
                                                                      .isOrganizer,
                                                              isPremium:
                                                                  forumState
                                                                      .isPremium,
                                                              messageType:
                                                                  MessageType
                                                                      .systemChat,
                                                            );
                                                            updatesCubit
                                                                .sendMessage(
                                                              '$name ended the live call',
                                                              isOrganizer:
                                                                  forumState
                                                                      .isOrganizer,
                                                              isPremium:
                                                                  forumState
                                                                      .isPremium,
                                                              messageType:
                                                                  MessageType
                                                                      .systemAnnouncement,
                                                            );
                                                          }
                                                        },
                                                        // Header start gestures
                                                        // are test-only "cheat
                                                        // codes" for now, but
                                                        // are still restricted to
                                                        // the Updates tab for
                                                        // consistency with where
                                                        // call/stream/quiz
                                                        // creation now lives.
                                                        onStartLiveStream:
                                                            !isUpdatesTabActive
                                                                ? null
                                                                : () {
                                                                    PermissionAcks
                                                                        .ensureAcknowledged(
                                                                      context,
                                                                      PermissionAckType
                                                                          .camera,
                                                                      title:
                                                                          'Host Live Video Stream',
                                                                      description:
                                                                          'To host a live video stream, Lynk-X needs access to your camera and microphone.',
                                                                      icon: Icons
                                                                          .videocam_rounded,
                                                                      actionLabel:
                                                                          'Allow Camera & Mic',
                                                                      onReady:
                                                                          () async {
                                                                        final name = forumState.userName.isNotEmpty
                                                                            ? forumState.userName
                                                                            : 'Host';
                                                                        final vfId =
                                                                            forumState.forumId;
                                                                        final videoService =
                                                                            ForumVideoStreamService();
                                                                        videoService.forumId =
                                                                            vfId ??
                                                                                '';
                                                                        // Read cubits before the await below —
                                                                        // context shouldn't cross an async gap.
                                                                        final chatCubit =
                                                                            context.read<ForumChatCubit>();
                                                                        final updatesCubit =
                                                                            context.read<ForumUpdatesCubit>();
                                                                        videoService
                                                                            .setLive(true);
                                                                        videoService
                                                                            .setMinimized(false);
                                                                        MiniOverlayService().activateLiveStream(
                                                                            hostName:
                                                                                name);

                                                                        if (vfId !=
                                                                                null &&
                                                                            vfId.isNotEmpty) {
                                                                          final sessionId =
                                                                              await videoService.createCloudflareSession(vfId);
                                                                          if (sessionId ==
                                                                              null) {
                                                                            videoService.setLive(false);
                                                                            MiniOverlayService().endPipSession();
                                                                            if (mounted &&
                                                                                context.mounted) {
                                                                              AppSnackBars.showError(context, 'Could not start your Cloudflare session — please try again.');
                                                                            }
                                                                            return;
                                                                          }
                                                                          // The HOST's own session IS the host
                                                                          // session — keeps hostSessionIdNotifier
                                                                          // (used by _LiveStreamJoinCard's
                                                                          // end-detection fast path) current for
                                                                          // the host too, not just listeners/
                                                                          // co-hosts (see subscribeToRemoteVideo's
                                                                          // own comment).
                                                                          videoService
                                                                              .hostSessionIdNotifier
                                                                              .value = sessionId;

                                                                          // Call-summary row must exist BEFORE
                                                                          // joinAsCallParticipant (needs its id) and
                                                                          // before updateForumStreamingConfig (which
                                                                          // now carries it, so any later client can
                                                                          // discover it) — see ForumAudioStreamCubit
                                                                          // .startAudioStream for the matching audio
                                                                          // reordering and full rationale.
                                                                          String?
                                                                              callSummaryId;
                                                                          final vfCreatedAt =
                                                                              forumState.forumCreatedAt;
                                                                          if (vfCreatedAt !=
                                                                              null) {
                                                                            callSummaryId =
                                                                                await videoService.startCallSummary(
                                                                              forumId: vfId,
                                                                              forumCreatedAt: vfCreatedAt,
                                                                              hostId: cubit.userId,
                                                                              sessionId: sessionId,
                                                                            );
                                                                            videoService.callSummaryId =
                                                                                callSummaryId;
                                                                          }

                                                                          // The host claims their own speaker slot
                                                                          // the same way a co-host does — see
                                                                          // social.join_as_call_participant's doc
                                                                          // comment for why there is no separate
                                                                          // host-registration path.
                                                                          if (callSummaryId !=
                                                                              null) {
                                                                            await videoService.joinAsCallParticipant(
                                                                              forumId: vfId,
                                                                              callSummaryId: callSummaryId,
                                                                              cfSessionId: sessionId,
                                                                              trackName: cubit.userId,
                                                                            );
                                                                            videoService.participantsNotifier.value =
                                                                                {
                                                                              cubit.userId: CallParticipant(
                                                                                userId: cubit.userId,
                                                                                userName: name,
                                                                                cfSessionId: sessionId,
                                                                                trackName: cubit.userId,
                                                                              ),
                                                                            };
                                                                          }

                                                                          try {
                                                                            await videoService.updateForumStreamingConfig(
                                                                              forumId: vfId,
                                                                              isLive: true,
                                                                              sessionId: sessionId,
                                                                              hostId: cubit.userId,
                                                                              callSummaryId: callSummaryId,
                                                                            );
                                                                          } catch (e) {
                                                                            debugPrint('[ForumScreen] video updateForumStreamingConfig failed: $e');
                                                                          }
                                                                        }

                                                                        chatCubit
                                                                            .sendMessage(
                                                                          '$name started the live stream',
                                                                          isOrganizer:
                                                                              forumState.isOrganizer,
                                                                          isPremium:
                                                                              forumState.isPremium,
                                                                          messageType:
                                                                              MessageType.systemChat,
                                                                        );
                                                                        updatesCubit
                                                                            .sendMessage(
                                                                          '$name started the live stream',
                                                                          isOrganizer:
                                                                              forumState.isOrganizer,
                                                                          isPremium:
                                                                              forumState.isPremium,
                                                                          messageType:
                                                                              MessageType.systemAnnouncement,
                                                                        );
                                                                      },
                                                                    );
                                                                  },
                                                        onStartAudioStream:
                                                            !isUpdatesTabActive
                                                                ? null
                                                                : () {
                                                                    PermissionAcks
                                                                        .ensureAcknowledged(
                                                                      context,
                                                                      PermissionAckType
                                                                          .microphone,
                                                                      title:
                                                                          'Host Audio Stream',
                                                                      description:
                                                                          'To start a live audio stream and speak with attendees, Lynk-X needs access to your microphone.',
                                                                      icon: Icons
                                                                          .mic_rounded,
                                                                      actionLabel:
                                                                          'Allow Microphone',
                                                                      onReady:
                                                                          () {
                                                                        final name = forumState.userName.isNotEmpty
                                                                            ? forumState.userName
                                                                            : 'Host';
                                                                        MiniOverlayService().activateLiveCall(
                                                                            hostName:
                                                                                name);
                                                                        audioCubit
                                                                            .startAudioStream();
                                                                        context
                                                                            .read<ForumChatCubit>()
                                                                            .sendMessage(
                                                                              '$name started the live call',
                                                                              isOrganizer: forumState.isOrganizer,
                                                                              isPremium: forumState.isPremium,
                                                                              messageType: MessageType.systemChat,
                                                                            );
                                                                        context
                                                                            .read<ForumUpdatesCubit>()
                                                                            .sendMessage(
                                                                              '$name started the live call',
                                                                              isOrganizer: forumState.isOrganizer,
                                                                              isPremium: forumState.isPremium,
                                                                              messageType: MessageType.systemAnnouncement,
                                                                            );
                                                                      },
                                                                    );
                                                                  },
                                                        isOrganizer: forumState
                                                            .isOrganizer,
                                                        isReadOnly: forumState
                                                            .isReadOnly,
                                                        forumName: forumState
                                                            .forumName,
                                                        onLockToggle: () {
                                                          final nextStatus =
                                                              forumState
                                                                      .isReadOnly
                                                                  ? 'open'
                                                                  : 'read_only';
                                                          cubit
                                                              .updateForumStatus(
                                                                  nextStatus);
                                                          AppSnackBars.showInfo(
                                                            context,
                                                            forumState
                                                                    .isReadOnly
                                                                ? 'Chat unlocked'
                                                                : 'Chat locked',
                                                          );
                                                        },
                                                        onSearch: (q) {
                                                          context
                                                              .read<
                                                                  ForumUpdatesCubit>()
                                                              .setSearchQuery(
                                                                  q);
                                                          context
                                                              .read<
                                                                  ForumChatCubit>()
                                                              .setSearchQuery(
                                                                  q);
                                                        },
                                                        onSearchToggle: () {
                                                          final updatesCubit =
                                                              context.read<
                                                                  ForumUpdatesCubit>();
                                                          final chatCubit =
                                                              context.read<
                                                                  ForumChatCubit>();
                                                          if (updatesCubit
                                                                  .state
                                                                  .searchQuery
                                                                  .isNotEmpty ||
                                                              chatCubit
                                                                  .state
                                                                  .searchQuery
                                                                  .isNotEmpty) {
                                                            updatesCubit
                                                                .setSearchQuery(
                                                                    '');
                                                            chatCubit
                                                                .setSearchQuery(
                                                                    '');
                                                          }
                                                        },
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                              if (hasAds)
                                                RepaintBoundary(
                                                  child: AdCarousel(
                                                    ads: adsState.ads,
                                                    onAdViewed: (ad) => context
                                                        .read<ForumAdsCubit>()
                                                        .logAdImpression(ad),
                                                    onAdViewEnded: (adId) =>
                                                        context
                                                            .read<
                                                                ForumAdsCubit>()
                                                            .cancelAdImpression(
                                                                adId),
                                                    onAdClicked: (ad) async {
                                                      context
                                                          .read<ForumAdsCubit>()
                                                          .logAdClick(ad);
                                                      if (ad.targetUrl !=
                                                          null) {
                                                        final uri = Uri.parse(
                                                            ad.targetUrl!);
                                                        if (await canLaunchUrl(
                                                            uri)) {
                                                          await launchUrl(uri);
                                                        }
                                                      } else if (ad
                                                              .targetEventId !=
                                                          null) {
                                                        context.push(
                                                            '/events/${ad.targetEventId}');
                                                      }
                                                    },
                                                  ),
                                                ),
                                              if (!isStageActive) ...[
                                                ForumTabBar(
                                                  onTabSelected: _navigateToTab,
                                                ),
                                                if (extraHeaderWidgets != null)
                                                  extraHeaderWidgets,
                                              ],
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
                      body: isStageActive
                          ? BlocBuilder<ForumAdsCubit, ForumAdsState>(
                              builder: (context, adsState) {
                                final forumState =
                                    context.read<ForumCubit>().state;
                                final hasAds = ForumConfig.showBannerAd(
                                  isPremium: forumState.isPremium,
                                  bannerEnabled: context
                                      .read<FeatureFlagCubit>()
                                      .isEnabled('enable_banner_ad'),
                                  forumAdsEnabled: context
                                      .read<FeatureFlagCubit>()
                                      .isEnabled('enable_forum_ads'),
                                  hasAdsContent: adsState.ads.isNotEmpty,
                                );
                                final stageHeaderHeight =
                                    56.0 + (hasAds ? 50.0 : 0.0);

                                return Padding(
                                  padding:
                                      EdgeInsets.only(top: stageHeaderHeight),
                                  child: ForumVideoStage(
                                    forumName: forumState.forumName,
                                    hostName: cubit.state.userName,
                                    isHost: forumState.isOrganizer,
                                    forumId: forumState.forumId,
                                  ),
                                );
                              },
                            )
                          : _buildTabContent(),
                    );
                  },
                );
              },
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
            BlocBuilder<ForumCubit, ForumState>(
              builder: (context, state) {
                return MiniOverlay(
                  forumName: state.forumName,
                  hostName: state.userName,
                  isHost: state.isOrganizer,
                );
              },
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

  // Poll/quiz creation is Updates-tab-only (Live Chat only ever receives the
  // resulting announcement), so these no longer branch on which tab was
  // active — they always target ForumUpdatesCubit's channel.
  void _showCreatePollOrQuizSheet() {
    final forumId = context.read<ForumCubit>().state.forumId;
    final isOrganizer = context.read<ForumCubit>().state.isOrganizer;
    if (forumId == null || !isOrganizer) return;

    final channelId = context.read<ForumUpdatesCubit>().channelId;
    final channelCreatedAt =
        context.read<ForumUpdatesCubit>().channelCreatedAt?.toIso8601String();

    ForumAddOptionSheet.show(
      context: context,
      onCreatePoll: () => _showPollEditorSheet(
        forumId: forumId,
        channelId: channelId,
        channelCreatedAt: channelCreatedAt,
        messageType: 'update_poll',
      ),
      onCreateQuiz: _openQuizList,
    );
  }

  void _openQuizList() async {
    final forumId = context.read<ForumCubit>().state.forumId;
    final forumReference = context.read<ForumCubit>().forumReference;
    final isOrganizer = context.read<ForumCubit>().state.isOrganizer;
    if (forumId == null || !isOrganizer) return;

    final channelId = context.read<ForumUpdatesCubit>().channelId;
    final channelCreatedAt =
        context.read<ForumUpdatesCubit>().channelCreatedAt?.toIso8601String();

    final result = await context.push<Map<String, dynamic>>(
      '/forum/$forumReference/quiz/list',
      extra: {
        'forumId': forumId,
        'isOrganizer': true,
        'isLiveChat': false,
        'channelId': channelId,
        'channelCreatedAt': channelCreatedAt,
      },
    );
    if (result == null || !context.mounted) return;
    _pushCreatedQuizMessage(messageType: 'update_quiz', result: result);
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
            return PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) =>
                  context.read<ForumCubit>().setTabIndex(index),
              children: [
                showUpdates
                    ? UpdatesTab(
                        scrollController: _updatesScrollController,
                        onActionTap: () => _navigateToTab(2),
                        onMediaTap: (url) => _viewMedia(url),
                        onCreatePollOrQuiz: _showCreatePollOrQuizSheet,
                      )
                    : const SizedBox.shrink(),
                showChat
                    ? LiveChatTab(
                        scrollController: _chatScrollController,
                        selectedEmoji: state.selectedEmoji,
                        emojiTrigger: state.emojiTrigger,
                        onActionTap: () => _navigateToTab(2),
                        onMediaTap: (url) => _viewMedia(url),
                        // Poll/quiz creation is Updates-tab-only — Live Chat
                        // shows the resulting system announcement but never
                        // originates one. Passing null hides the composer's
                        // "+" button entirely (see MessageInput).
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
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _pushCreatedQuizMessage({
    required String messageType,
    required Map<String, dynamic> result,
  }) {
    final messageId = result['messageId'] as String?;
    final createdAt = result['createdAt'] as DateTime?;
    final title = result['title'] as String?;
    if (messageId == null || createdAt == null) return;

    final updatesCubit = context.read<ForumUpdatesCubit>();
    updatesCubit.onBroadcastMessageReceived(ChatMessage(
      id: messageId,
      sender: updatesCubit.userName,
      userId: updatesCubit.userId,
      message: title ?? '',
      createdAt: createdAt,
      isMe: true,
      type: MessageType.fromValue(messageType),
    ));

    // Deliberately NOT systemAnnouncement/systemChat: MessageType
    // .isLiveAnnouncement (and the literal "started the live call/stream"
    // string checks in ChatMessage.isLiveSessionEvent) key JoinCard
    // rendering in the Updates tab off exactly those types. Reusing them
    // here would make this plain-text quiz pointer misdetect as a live
    // call/stream announcement and render a broken JoinCard pointing at
    // nothing. Plain chat renders as a normal bubble instead — correct, if
    // slightly less styled than a real system message.
    final forumState = context.read<ForumCubit>().state;
    final name = forumState.userName.isNotEmpty ? forumState.userName : 'Host';
    final announcement =
        '$name started a live quiz${title != null && title.isNotEmpty ? ': $title' : ''}';
    context.read<ForumChatCubit>().sendMessage(
          announcement,
          isOrganizer: forumState.isOrganizer,
          isPremium: forumState.isPremium,
          messageType: MessageType.chat,
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

  void _handleMentionMedia(ForumMedia media) {
    _navigateToTab(1);
    context.read<ForumChatCubit>().setMentionedMedia(media);
  }

  void _viewForumMedia(ForumMedia item) {
    final mediaCubit = context.read<ForumMediaCubit>();
    final forumCubit = context.read<ForumCubit>();
    final isAuthorized =
        forumCubit.state.isOrganizer || forumCubit.state.isModerator;
    final isUploader = item.uploaderId == forumCubit.userId;
    final showChat = context
        .read<FeatureFlagCubit>()
        .isEnabled('enable_forum_live_chat');

    MediaViewer.show(
      context,
      imageUrl: item.url,
      mediaItem: item,
      onMention: showChat ? _handleMentionMedia : null,
      onApprove: (isAuthorized && !item.isApproved)
          ? () => mediaCubit.approveMedia(item)
          : null,
      onReject: (isAuthorized || isUploader)
          ? () => mediaCubit.deleteMedia(item)
          : null,
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
    final audioState = context.watch<ForumAudioStreamCubit>().state;

    return PresenceDrawer(
      members: forumState.members,
      onlineUsers: presenceState.onlineUsers,
      eventProgress: forumState.eventProgress,
      isPremium: forumState.isPremium,
      isOrganizer: forumState.isOrganizer,
      isAudioLive: audioState.isLive,
      eventId: forumState.eventId,
      forumId: forumId,
      isLoading: presenceState.isLoading,
      eventCreatedAt: forumState.eventCreatedAt,
      onEventProgressTap: onEventProgressTap,
    );
  }
}
