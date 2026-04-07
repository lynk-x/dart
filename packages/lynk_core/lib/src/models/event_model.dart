import 'package:equatable/equatable.dart';

/// Represents a single event entry in the Lynk-X ecosystem.
///
/// Fields align with the common events database schema.
class EventModel extends Equatable {
  final String id;
  final String title;
  final String description;
  final DateTime startDatetime;
  final DateTime endDatetime;
  final String? locationName;
  final String? thumbnailUrl;
  final String? category;
  final int chatCount;

  const EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.startDatetime,
    required this.endDatetime,
    this.locationName,
    this.thumbnailUrl,
    this.category,
    this.chatCount = 0,
  });

  bool get isPassed => startDatetime.isBefore(DateTime.now());
  bool get hasUnread => chatCount > 0;

  factory EventModel.fromMap(Map<String, dynamic> map) {
    return EventModel(
      id: (map['event_id'] ?? map['id']) as String,
      title: (map['event_title'] ?? map['title']) as String,
      description: map['description'] as String? ?? '',
      startDatetime: DateTime.parse(
          (map['event_starts_at'] ?? map['starts_at']) as String),
      endDatetime:
          DateTime.parse((map['event_ends_at'] ?? map['ends_at']) as String),
      locationName: map['location_name'] as String?,
      thumbnailUrl:
          (map['event_thumbnail_url'] ?? map['thumbnail_url']) as String?,
      category: map['category_name'] as String?,
      chatCount: (map['chat_count'] as int?) ??
          (map['has_unread_activity'] == true ? 1 : 0),
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        startDatetime,
        endDatetime,
        locationName,
        thumbnailUrl,
        category,
        chatCount,
      ];
}
