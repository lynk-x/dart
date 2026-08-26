import 'package:flutter/material.dart';

/// Represents a single message within the Forum.
///
/// Supports rich content including:
/// - Reply threading ([replyTo])
/// - Content categorization ([category]) for filtering
/// - Role badges ([role], [roleColor]) for organizers/speakers
/// - Link previews ([linkPreviewTitle], [linkPreviewUrl])
/// - In-app navigation ([targetRoute]) for clickable action cards
enum MessageType {
  chat,
  announcement,
  systemAnnouncement,
  systemChat,
  livechatPoll,
  livechatQuiz,
  updatePoll,
  updateQuiz,
  streamChat,
  streamEvent;

  /// True if this is an automated system message.
  bool get isSystem =>
      this == systemChat || this == systemAnnouncement || this == streamEvent;

  /// True if this value maps to a live-call or live-stream announcement
  /// (used by JoinCard detection — avoids string scanning in widgets).
  bool get isLiveAnnouncement =>
      this == systemAnnouncement || this == streamEvent;

  /// True if this message IS a poll/quiz (see surveys.polls / quiz_sessions,
  /// keyed on this message's own id) rather than a plain chat/announcement.
  bool get isPollOrQuiz =>
      this == livechatPoll ||
      this == livechatQuiz ||
      this == updatePoll ||
      this == updateQuiz;

  bool get isPoll => this == livechatPoll || this == updatePoll;
  bool get isQuiz => this == livechatQuiz || this == updateQuiz;
  bool get isStreamMessage => this == streamChat || this == streamEvent;
  bool get isLiveChat => this == chat || this == streamChat || this == livechatPoll || this == livechatQuiz || this == systemChat;

  static MessageType fromValue(String? value) {
    switch (value) {
      case 'announcement':
        return MessageType.announcement;
      case 'system_announcement':
        return MessageType.systemAnnouncement;
      case 'system_chat':
        return MessageType.systemChat;
      case 'livechat_poll':
        return MessageType.livechatPoll;
      case 'livechat_quiz':
        return MessageType.livechatQuiz;
      case 'update_poll':
        return MessageType.updatePoll;
      case 'update_quiz':
        return MessageType.updateQuiz;
      case 'stream_chat':
        return MessageType.streamChat;
      case 'stream_event':
        return MessageType.streamEvent;
      default:
        return MessageType.chat;
    }
  }

  String get value {
    switch (this) {
      case MessageType.announcement:
        return 'announcement';
      case MessageType.systemAnnouncement:
        return 'system_announcement';
      case MessageType.systemChat:
        return 'system_chat';
      case MessageType.livechatPoll:
        return 'livechat_poll';
      case MessageType.livechatQuiz:
        return 'livechat_quiz';
      case MessageType.updatePoll:
        return 'update_poll';
      case MessageType.updateQuiz:
        return 'update_quiz';
      case MessageType.streamChat:
        return 'stream_chat';
      case MessageType.streamEvent:
        return 'stream_event';
      case MessageType.chat:
        return 'chat';
    }
  }
}

/// Compiled once per process — matches http/https/ftp URLs.
final _kUrlRegExp =
    RegExp(r'(?:(?:https?|ftp)://)([\w/\-?=%.]+\.[\w/\-?=%.]+)');

/// Expando cache for [ChatMessage.urlMatch]. Lives outside the object so
/// [ChatMessage] can keep its `const` constructor.
final _urlMatchExpando = Expando<Object>('url_match');

/// Sentinel value placed in [_urlMatchExpando] when the regex found no match,
/// to distinguish "not yet computed" (null slot) from "computed, no URL found".
final _kNoUrlSentinel = Object();

class ChatMessage {
  final String id;
  final String sender;
  final String userId;
  final String message;
  final DateTime createdAt;
  final bool isMe;
  final MessageType type;

  final String? role;
  final Color? roleColor;
  final ChatMessage? replyTo;
  final String? imageUrl;
  final String? thumbnailUrl;
  final String? linkPreviewTitle;
  final String? linkPreviewUrl;
  final String? targetRoute;

  /// Category tag mapping to message_hashtag (e.g. 'Urgent', 'Activity', 'Q&A', 'Resources', 'Rules').
  final String? category;
  final Map<String, int> reactions;
  final bool isSending;
  final bool hasError;
  final bool isPinned;
  final bool isPremium;
  final bool isEdited;

  bool get isLiveSessionEvent {
    if (type.isLiveAnnouncement) return true;
    final lower = message.toLowerCase();
    return lower.contains('started the live stream') ||
        lower.contains('started the live call') ||
        lower.contains('ended the live stream') ||
        lower.contains('ended the live call');
  }

  bool get isJoinSystemMessage {
    final lower = message.toLowerCase();
    return lower.contains('joined the live stream') ||
        lower.contains('joined the live call') ||
        lower.contains('joined the quiz session');
  }

  RegExpMatch? get urlMatch {
    final cached = _urlMatchExpando[this];
    if (cached == _kNoUrlSentinel) return null;
    if (cached != null) return cached as RegExpMatch;
    final result = _kUrlRegExp.firstMatch(message);
    _urlMatchExpando[this] = result ?? _kNoUrlSentinel;
    return result;
  }

  /// Extracts the memoized URL matched in [message], prefixed with `https://` if needed.
  String? get resolvedUrl {
    final match = urlMatch;
    if (match == null) return null;
    final raw = message.substring(match.start, match.end);
    return raw.startsWith('http') ? raw : 'https://$raw';
  }

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.userId,
    required this.message,
    required this.createdAt,
    required this.isMe,
    required this.type,
    this.role,
    this.roleColor,
    this.replyTo,
    this.imageUrl,
    this.thumbnailUrl,
    this.linkPreviewTitle,
    this.linkPreviewUrl,
    this.targetRoute,
    this.category,
    this.reactions = const {},
    this.isSending = false,
    this.hasError = false,
    this.isPinned = false,
    this.isPremium = false,
    this.isEdited = false,
  });

  /// The relative time to display in UI (e.g., "2m ago")
  String get relativeTime {
    final difference = DateTime.now().difference(createdAt);
    if (difference.inSeconds < 60) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map, String currentUserId) {
    Map<String, int> parsedReactions = {};
    if (map['reactions'] != null) {
      parsedReactions = Map<String, int>.from(map['reactions'] as Map);
    }

    return ChatMessage(
      id: map['id'] as String,
      sender: map['user_profile']?['user_name'] as String? ??
              map['user_profile']?['full_name'] as String? ??
              'Deleted User',
      userId: map['author_id'] as String? ?? map['user_id'] as String? ?? '',
      message: map['content'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      isMe: (map['author_id']?.toString().toLowerCase() == currentUserId.toLowerCase()) ||
            (map['user_id']?.toString().toLowerCase() == currentUserId.toLowerCase()),
      type: MessageType.fromValue(map['message_type'] as String?),
      category: map['hashtag'] as String?,
      role: map['forum_members']?['role_id'] as String?,
      imageUrl: map['forum_media']?['url'] as String?,
      thumbnailUrl: map['forum_media']?['thumbnail_url'] as String?,
      reactions: parsedReactions,
      isPinned: map['is_pinned'] == true,
      isPremium: map['user_profile']?['is_premium'] == true,
      isEdited: (map['edit_count'] as num? ?? 0) > 0 || map['is_edited'] == true,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? sender,
    String? userId,
    String? message,
    DateTime? createdAt,
    bool? isMe,
    MessageType? type,
    String? role,
    Color? roleColor,
    ChatMessage? replyTo,
    String? imageUrl,
    String? thumbnailUrl,
    String? linkPreviewTitle,
    String? linkPreviewUrl,
    String? targetRoute,
    String? category,
    Map<String, int>? reactions,
    bool? isSending,
    bool? hasError,
    bool? isPinned,
    bool? isPremium,
    bool? isEdited,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      userId: userId ?? this.userId,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      isMe: isMe ?? this.isMe,
      type: type ?? this.type,
      role: role ?? this.role,
      roleColor: roleColor ?? this.roleColor,
      replyTo: replyTo ?? this.replyTo,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      linkPreviewTitle: linkPreviewTitle ?? this.linkPreviewTitle,
      linkPreviewUrl: linkPreviewUrl ?? this.linkPreviewUrl,
      targetRoute: targetRoute ?? this.targetRoute,
      category: category ?? this.category,
      reactions: reactions ?? this.reactions,
      isSending: isSending ?? this.isSending,
      hasError: hasError ?? this.hasError,
      isPinned: isPinned ?? this.isPinned,
      isPremium: isPremium ?? this.isPremium,
      isEdited: isEdited ?? this.isEdited,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': message,
      'author_id': userId,
      'created_at': createdAt.toIso8601String(),
      'message_type': type.value,
      'hashtag': category,
      'is_pinned': isPinned,
      'reactions': reactions,
      'is_edited': isEdited,
      'user_profile': {
        'user_name': sender,
        'is_premium': isPremium,
      },
      'forum_members': {'role_id': role},
      'forum_media': {
        'url': imageUrl,
        'thumbnail_url': thumbnailUrl,
      },
    };
  }
}

/// Represents a single advertisement displayed in the [AdCarousel].
class AdModel {
  final String id;
  final String title;
  final String callToAction;
  final String? targetUrl;
  final String? targetEventId;
  final String? imageUrl;

  /// HMAC-signed proof-of-serve from the ad matcher (metadata.serve_token).
  final String? serveToken;

  const AdModel({
    required this.id,
    this.title = 'AD',
    required this.callToAction,
    this.targetUrl,
    this.targetEventId,
    this.imageUrl,
    this.serveToken,
  });

  factory AdModel.fromMap(Map<String, dynamic> map) {
    final assets = map['ad_media'] as List<dynamic>?;
    final firstAsset =
        assets != null && assets.isNotEmpty ? assets.first : null;
    final metadata = map['metadata'] as Map<String, dynamic>? ?? {};

    return AdModel(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'AD',
      callToAction: firstAsset?['call_to_action'] as String? ??
          metadata['call_to_action'] as String? ??
          'Learn More',
      targetUrl: map['target_url'] as String? ?? metadata['target_url'] as String?,
      targetEventId: map['target_event_id'] as String?,
      imageUrl:
          firstAsset?['url'] as String? ?? metadata['image_url'] as String?,
      serveToken: metadata['serve_token'] as String?,
    );
  }
}

/// Represents a media item uploaded to the forum.
class ForumMedia {
  final String id;
  final String url;
  final String? thumbnailUrl;
  final String mediaType;
  final String? caption;
  final String? uploaderId;
  final String? uploaderName;
  final bool isApproved;
  final DateTime createdAt;

  const ForumMedia({
    required this.id,
    required this.url,
    this.thumbnailUrl,
    required this.mediaType,
    this.caption,
    this.uploaderId,
    this.uploaderName,
    this.isApproved = true,
    required this.createdAt,
  });

  factory ForumMedia.fromMap(Map<String, dynamic> map) {
    final mediaUrl = map['media_url'] as Map<String, dynamic>? ?? {};
    final uploaderProfile = map['user_profile'] as Map<String, dynamic>?;
    return ForumMedia(
      id: map['id'] as String,
      url: mediaUrl['full_res'] as String? ?? map['url'] as String? ?? '',
      thumbnailUrl: mediaUrl['thumbnail'] as String? ?? map['thumbnail_url'] as String?,
      mediaType: map['media_type'] as String? ?? 'image',
      caption: map['caption'] as String?,
      uploaderId: uploaderProfile?['id'] as String? ??
          (map['uploader_id'] is String ? map['uploader_id'] as String : null),
      uploaderName: uploaderProfile?['user_name'] as String? ??
          uploaderProfile?['full_name'] as String? ??
          map['uploader_name'] as String?,
      isApproved: map['is_approved'] == true,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'url': url,
      'thumbnail_url': thumbnailUrl,
      'media_type': mediaType,
      'caption': caption,
      'uploader_id': uploaderId,
      'is_approved': isApproved,
      'created_at': createdAt.toIso8601String(),
    };
  }

  ForumMedia copyWith({
    String? id,
    String? url,
    String? thumbnailUrl,
    String? mediaType,
    String? caption,
    String? uploaderId,
    String? uploaderName,
    bool? isApproved,
    DateTime? createdAt,
  }) {
    return ForumMedia(
      id: id ?? this.id,
      url: url ?? this.url,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      mediaType: mediaType ?? this.mediaType,
      caption: caption ?? this.caption,
      uploaderId: uploaderId ?? this.uploaderId,
      uploaderName: uploaderName ?? this.uploaderName,
      isApproved: isApproved ?? this.isApproved,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class LinkPreviewData {
  final String? title;
  final String? description;
  final String? image;
  final String? url;

  const LinkPreviewData({
    this.title,
    this.description,
    this.image,
    this.url,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'image': image,
      'url': url,
    };
  }

  factory LinkPreviewData.fromMap(Map<String, dynamic> map) {
    return LinkPreviewData(
      title: map['title'] as String?,
      description: map['description'] as String?,
      image: map['image'] as String?,
      url: map['url'] as String?,
    );
  }
}

class ForumCategory {
  static const List<String> values = [
    'Urgent',
    'Activity',
    'Q&A',
    'Resources',
    'Rules',
  ];

  static const Map<String, Color> colors = {
    'Urgent': Color(0xFFFF4444),
    'Activity': Color(0xFF00AAFF),
    'Q&A': Color(0xFFFFAA00),
    'Resources': Color(0xFF44DD88),
    'Rules': Color(0xFFAA88FF),
  };

  static Color getColorForCategory(String category, Color fallbackColor) {
    return colors[category] ?? fallbackColor;
  }
}

