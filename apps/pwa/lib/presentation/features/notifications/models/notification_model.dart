import 'package:flutter/material.dart';

enum NotificationType {
  system,
  marketing,
  mention,
  announcements,
  livechats,
  media,
  eventUpdate,
  moneyIn,
  moneyOut,
  ticketResaleOffer,
}

class NotificationModel {
  final String id;
  final String userId;
  final NotificationType type;
  final String title;
  final String? body;
  final Map<String, dynamic>? data;
  final String? actionUrl;
  final bool isRead;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    this.body,
    this.data,
    this.actionUrl,
    this.isRead = false,
    required this.createdAt,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      type: _parseType(map['type'] as String?),
      title: map['title'] as String,
      body: map['body'] as String?,
      data: map['data'] as Map<String, dynamic>?,
      actionUrl: map['action_url'] as String?,
      isRead: map['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  static NotificationType _parseType(String? typeStr) {
    switch (typeStr) {
      case 'marketing':
        return NotificationType.marketing;
      case 'mention':
        return NotificationType.mention;
      case 'announcements':
        return NotificationType.announcements;
      case 'livechats':
        return NotificationType.livechats;
      case 'media':
        return NotificationType.media;
      case 'event_update':
        return NotificationType.eventUpdate;
      case 'money_in':
        return NotificationType.moneyIn;
      case 'money_out':
        return NotificationType.moneyOut;
      case 'ticket_resale_offer':
        return NotificationType.ticketResaleOffer;
      case 'system':
      default:
        return NotificationType.system;
    }
  }

  NotificationModel copyWith({
    String? id,
    String? userId,
    NotificationType? type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    String? actionUrl,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      actionUrl: actionUrl ?? this.actionUrl,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  IconData get icon {
    switch (type) {
      case NotificationType.system:
        return Icons.system_update;
      case NotificationType.marketing:
        return Icons.campaign;
      case NotificationType.mention:
        return Icons.alternate_email;
      case NotificationType.announcements:
        return Icons.announcement;
      case NotificationType.livechats:
        return Icons.chat;
      case NotificationType.media:
        return Icons.perm_media;
      case NotificationType.eventUpdate:
        return Icons.event;
      case NotificationType.moneyIn:
        return Icons.account_balance_wallet;
      case NotificationType.moneyOut:
        return Icons.payment;
      case NotificationType.ticketResaleOffer:
        return Icons.sell;
    }
  }

  Color get color {
    switch (type) {
      case NotificationType.system:
        return Colors.blue;
      case NotificationType.marketing:
        return Colors.orange;
      case NotificationType.mention:
        return Colors.yellow;
      case NotificationType.announcements:
        return Colors.cyan;
      case NotificationType.livechats:
        return Colors.indigo;
      case NotificationType.media:
        return Colors.pink;
      case NotificationType.eventUpdate:
        return Colors.green;
      case NotificationType.moneyIn:
        return Colors.teal;
      case NotificationType.moneyOut:
        return Colors.red;
      case NotificationType.ticketResaleOffer:
        return Colors.orange;
    }
  }
}
