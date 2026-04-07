import 'package:equatable/equatable.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';

/// Represents the global state of the Forum feature.
class ForumState extends Equatable {
  final String forumStatus;
  final int currentTabIndex;

  // ── Shared Content ─────────────────────────────────────────────────────────
  final ForumMedia? mentionedMedia;
  final List<Map<String, dynamic>> members;

  // ── Metadata/Permissions ───────────────────────────────────────────────────
  final String? eventId;
  final bool isOrganizer;
  final bool isModerator;
  final bool isMuted;
  final bool isPremium;
  final bool hasMutedLiveChatsMedia;
  final bool showAds;

  // ── Reactions & Global Animations ──────────────────────────────────────────
  final String selectedEmoji;
  final int emojiTrigger;
  final double eventProgress;
  final String? waveFromName;
  final String? waveFromUserId;
  final int waveTrigger;

  bool get isReadOnly => forumStatus == 'read_only';

  const ForumState({
    this.forumStatus = 'active',
    this.currentTabIndex = 0,
    this.mentionedMedia,
    this.members = const [],
    this.eventId,
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
    String? forumStatus,
    int? currentTabIndex,
    ForumMedia? mentionedMedia,
    bool clearMentionedMedia = false,
    List<Map<String, dynamic>>? members,
    String? eventId,
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
      forumStatus: forumStatus ?? this.forumStatus,
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
      mentionedMedia: clearMentionedMedia
          ? null
          : mentionedMedia ?? this.mentionedMedia,
      members: members ?? this.members,
      eventId: eventId ?? this.eventId,
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
    forumStatus,
    currentTabIndex,
    mentionedMedia,
    members,
    eventId,
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
