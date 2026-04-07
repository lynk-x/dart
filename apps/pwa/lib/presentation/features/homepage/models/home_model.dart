import 'package:equatable/equatable.dart';

/// Represents a single event entry in the home feed.
///
/// Fields align with the `events` table in the Supabase DB schema
/// (see `refinement_05_core_tables.sql`). Only the columns needed
/// for list display are included here.
class EventModel extends Equatable {
  final String id;
  final String title;
  final String description;
  final DateTime startDatetime;
  final DateTime endDatetime;

  /// Optional human-readable location string (e.g. "Nairobi, Kenya").
  final String? locationName;

  /// Square/portrait thumbnail URL served from Supabase Storage.
  final String? thumbnailUrl;

  /// Category string (e.g. 'Arts&Entertainment', 'Business&Professional').
  final String? category;

  /// Whether the event has unread forum messages / activity.
  ///
  /// Used by the home feed sort algorithm (unread events bubble to the top
  /// within each date group).
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

  /// Whether the event's start time is in the past.
  bool get isPassed => startDatetime.isBefore(DateTime.now());

  /// Whether this event has unread forum activity.
  bool get hasUnread => chatCount > 0;

  /// Creates an [EventModel] from a Supabase row map.
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
