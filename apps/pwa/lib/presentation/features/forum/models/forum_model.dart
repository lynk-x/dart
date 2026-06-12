import 'package:flutter/material.dart';

/// Represents a single message within the Forum.
///
/// Supports rich content including:
/// - Reply threading ([replyTo])
/// - Content categorization ([category]) for filtering
/// - Role badges ([role], [roleColor]) for organizers/speakers
/// - Link previews ([linkPreviewTitle], [linkPreviewUrl])
/// - In-app navigation ([targetRoute]) for clickable action cards
enum MessageType { chat, announcement }

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
  /// If set, this message has an attached poll/quiz from the questionnaires table.
  final String? questionnaireId;
  final Map<String, int> reactions;
  final bool isSending;
  final bool hasError;
  final bool isPinned;
  final bool isPremium;

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
    this.questionnaireId,
    this.reactions = const {},
    this.isSending = false,
    this.hasError = false,
    this.isPinned = false,
    this.isPremium = false,
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
      sender: map['user_profile']?['user_name'] as String? ?? 'Deleted User',
      userId: map['author_id'] as String? ?? map['user_id'] as String? ?? '',
      message: map['content'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      isMe: (map['author_id']?.toString().toLowerCase() == currentUserId.toLowerCase()) ||
            (map['user_id']?.toString().toLowerCase() == currentUserId.toLowerCase()),
      type: map['message_type'] == 'announcement'
          ? MessageType.announcement
          : MessageType.chat,
      category: map['hashtag'] as String?,
      questionnaireId: map['questionnaire_id'] as String?,
      role: map['forum_members']?['role_id'] as String?,
      imageUrl: map['forum_media']?['url'] as String?,
      thumbnailUrl: map['forum_media']?['thumbnail_url'] as String?,
      reactions: parsedReactions,
      isPinned: map['is_pinned'] == true,
      isPremium: map['user_profile']?['is_premium'] == true,
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
    String? questionnaireId,
    Map<String, int>? reactions,
    bool? isSending,
    bool? hasError,
    bool? isPinned,
    bool? isPremium,
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
      questionnaireId: questionnaireId ?? this.questionnaireId,
      reactions: reactions ?? this.reactions,
      isSending: isSending ?? this.isSending,
      hasError: hasError ?? this.hasError,
      isPinned: isPinned ?? this.isPinned,
      isPremium: isPremium ?? this.isPremium,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': message,
      'author_id': userId,
      'created_at': createdAt.toIso8601String(),
      'message_type':
          type == MessageType.announcement ? 'announcement' : 'chat',
      'hashtag': category,
      'is_pinned': isPinned,
      'reactions': reactions,
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

  const AdModel({
    required this.id,
    this.title = 'AD',
    required this.callToAction,
    this.targetUrl,
    this.targetEventId,
    this.imageUrl,
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
  final bool isApproved;
  final DateTime createdAt;

  const ForumMedia({
    required this.id,
    required this.url,
    this.thumbnailUrl,
    required this.mediaType,
    this.caption,
    this.uploaderId,
    this.isApproved = true,
    required this.createdAt,
  });

  factory ForumMedia.fromMap(Map<String, dynamic> map) {
    final mediaUrl = map['media_url'] as Map<String, dynamic>? ?? {};
    return ForumMedia(
      id: map['id'] as String,
      url: mediaUrl['full_res'] as String? ?? map['url'] as String? ?? '',
      thumbnailUrl: mediaUrl['thumbnail'] as String? ?? map['thumbnail_url'] as String?,
      mediaType: map['media_type'] as String? ?? 'image',
      caption: map['caption'] as String?,
      uploaderId: map['uploader_id'] as String?,
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

