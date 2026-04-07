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
    this.reactions = const {},
    this.isSending = false,
    this.hasError = false,
    this.isPinned = false,
    this.isPremium = false,
  });

  /// The relative time to display in UI (e.g., "2m ago")
  String get relativeTime {
    final difference = DateTime.now().difference(createdAt);
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map, String currentUserId) {
    Map<String, int> parsedReactions = {};
    if (map['vw_message_reaction_counts'] != null) {
      final List<dynamic> reactionsList =
          map['vw_message_reaction_counts'] as List<dynamic>;
      for (final reaction in reactionsList) {
        final emoji = reaction['emoji_code'] as String?;
        final count = reaction['reaction_count'] as int?;
        if (emoji != null && count != null) {
          parsedReactions[emoji] = count;
        }
      }
    } else if (map['reactions'] != null) {
      // Fallback for manual map passed in
      parsedReactions = Map<String, int>.from(map['reactions'] as Map);
    }

    return ChatMessage(
      id: map['id'] as String,
      sender: map['user_profile']?['full_name'] as String? ?? 'Deleted User',
      userId: map['author_id'] as String? ?? map['user_id'] as String? ?? '',
      message: map['content'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      isMe: (map['author_id'] ?? map['user_id']) == currentUserId,
      type: map['message_type'] == 'announcement'
          ? MessageType.announcement
          : MessageType.chat,
      category: map['hashtag'] as String?,
      role: map['forum_members']?['role_id'] as String?,
      imageUrl: map['forum_media']?['url'] as String?,
      thumbnailUrl: map['forum_media']?['thumbnail_url'] as String?,
      reactions: parsedReactions,
      isPinned: map['is_pinned'] == true,
      isPremium: map['user_profile']?['is_premium'] == true,
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
        'full_name': sender,
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
    final assets = map['ad_assets'] as List<dynamic>?;
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
    return ForumMedia(
      id: map['id'] as String,
      url: map['url'] as String,
      thumbnailUrl: map['thumbnail_url'] as String?,
      mediaType: map['media_type'] as String? ?? 'image',
      caption: map['caption'] as String?,
      uploaderId: map['uploader_id'] as String?,
      isApproved: map['is_approved'] == true,
      createdAt: DateTime.parse(map['created_at'] as String),
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
