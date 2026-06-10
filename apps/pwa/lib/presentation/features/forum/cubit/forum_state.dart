import 'package:equatable/equatable.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';

class ForumState extends Equatable {
  final String? forumId;
  final String forumStatus;
  final String forumName;
  final String userName;
  final int currentTabIndex;

  final ForumMedia? mentionedMedia;
  final List<Map<String, dynamic>> members;

  final String? eventId;
  final String? accountId;
  final DateTime? eventCreatedAt;
  final DateTime? forumCreatedAt;
  final String? channelId;
  final DateTime? channelCreatedAt;
  final bool isOrganizer;
  final bool isModerator;
  final bool isMuted;
  final bool isPremium;
  final bool hasMutedLiveChatsMedia;
  final bool showAds;

  final String selectedEmoji;
  final int emojiTrigger;
  final double eventProgress;
  final String? waveFromName;
  final String? waveFromUserId;
  final int waveTrigger;

  bool get isReadOnly => forumStatus == 'read_only';

  const ForumState({
    this.forumId,
    this.forumStatus = 'open',
    this.forumName = 'Community Forum',
    this.userName = 'A User',
    this.currentTabIndex = 0,
    this.mentionedMedia,
    this.members = const [],
    this.eventId,
    this.accountId,
    this.eventCreatedAt,
    this.forumCreatedAt,
    this.channelId,
    this.channelCreatedAt,
    this.isOrganizer = false,
    this.isModerator = false,
    this.isMuted = false,
    this.isPremium = false,
    this.hasMutedLiveChatsMedia = false,
    this.showAds = true,
    this.selectedEmoji = '',
    this.emojiTrigger = 0,
    this.eventProgress = 0.0,
    this.waveFromName,
    this.waveFromUserId,
    this.waveTrigger = 0,
  });

  ForumState copyWith({
    String? forumId,
    String? forumStatus,
    String? forumName,
    String? userName,
    int? currentTabIndex,
    ForumMedia? mentionedMedia,
    bool clearMentionedMedia = false,
    List<Map<String, dynamic>>? members,
    String? eventId,
    String? accountId,
    DateTime? eventCreatedAt,
    DateTime? forumCreatedAt,
    String? channelId,
    DateTime? channelCreatedAt,
    bool? isOrganizer,
    bool? isModerator,
    bool? isMuted,
    bool? isPremium,
    bool? hasMutedLiveChatsMedia,
    bool? showAds,
    String? selectedEmoji,
    int? emojiTrigger,
    double? eventProgress,
    String? waveFromName,
    String? waveFromUserId,
    int? waveTrigger,
  }) {
    return ForumState(
      forumId: forumId ?? this.forumId,
      forumStatus: forumStatus ?? this.forumStatus,
      forumName: forumName ?? this.forumName,
      userName: userName ?? this.userName,
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
      mentionedMedia: clearMentionedMedia
          ? null
          : mentionedMedia ?? this.mentionedMedia,
      members: members ?? this.members,
      eventId: eventId ?? this.eventId,
      accountId: accountId ?? this.accountId,
      eventCreatedAt: eventCreatedAt ?? this.eventCreatedAt,
      forumCreatedAt: forumCreatedAt ?? this.forumCreatedAt,
      channelId: channelId ?? this.channelId,
      channelCreatedAt: channelCreatedAt ?? this.channelCreatedAt,
      isOrganizer: isOrganizer ?? this.isOrganizer,
      isModerator: isModerator ?? this.isModerator,
      isMuted: isMuted ?? this.isMuted,
      isPremium: isPremium ?? this.isPremium,
      hasMutedLiveChatsMedia:
          hasMutedLiveChatsMedia ?? this.hasMutedLiveChatsMedia,
      showAds: showAds ?? this.showAds,
      selectedEmoji: selectedEmoji ?? this.selectedEmoji,
      emojiTrigger: emojiTrigger ?? this.emojiTrigger,
      eventProgress: eventProgress ?? this.eventProgress,
      waveFromName: waveFromName ?? this.waveFromName,
      waveFromUserId: waveFromUserId ?? this.waveFromUserId,
      waveTrigger: waveTrigger ?? this.waveTrigger,
    );
  }

  @override
  List<Object?> get props => [
        forumId,
        forumStatus,
        forumName,
        userName,
        currentTabIndex,
        mentionedMedia,
        members,
        eventId,
        accountId,
        eventCreatedAt,
        forumCreatedAt,
        channelId,
        channelCreatedAt,
        isOrganizer,
        isModerator,
        isMuted,
        isPremium,
        hasMutedLiveChatsMedia,
        showAds,
        selectedEmoji,
        emojiTrigger,
        eventProgress,
        waveFromName,
        waveFromUserId,
        waveTrigger,
      ];
}
