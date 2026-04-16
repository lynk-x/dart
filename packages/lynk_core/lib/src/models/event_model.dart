import 'package:equatable/equatable.dart';

/// Represents a single event entry in the Lynk-X ecosystem.
///
/// Fields align with the public.events schema and api.v1_events view.
/// starts_at / ends_at are the raw table columns; the view aliases them
/// as start_datetime / end_datetime — both are handled in fromMap.
class EventModel extends Equatable {
  final String id;
  final String title;
  final String description;
  final DateTime startDatetime;
  final DateTime endDatetime;
  final String? timezone;
  final String? locationName;
  final String? thumbnailUrl;
  final String? category;       // category_name from api.v1_events JOIN
  final String? categoryId;     // category_id FK
  final String? status;         // draft | published | cancelled | completed
  final bool isPrivate;
  final bool isOnline;
  final String? currency;
  final int? totalCapacity;
  final int chatCount;

  const EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.startDatetime,
    required this.endDatetime,
    this.timezone,
    this.locationName,
    this.thumbnailUrl,
    this.category,
    this.categoryId,
    this.status,
    this.isPrivate = false,
    this.isOnline = false,
    this.currency,
    this.totalCapacity,
    this.chatCount = 0,
  });

  bool get isPassed => startDatetime.isBefore(DateTime.now());
  bool get hasUnread => chatCount > 0;

  factory EventModel.fromMap(Map<String, dynamic> map) {
    // Accepts both raw table columns (starts_at) and view aliases (start_datetime /
    // event_starts_at from RPC results). Falls back safely rather than throwing.
    final startRaw = map['start_datetime']
        ?? map['starts_at']
        ?? map['event_starts_at'];
    final endRaw = map['end_datetime']
        ?? map['ends_at']
        ?? map['event_ends_at'];

    // location is a jsonb column: { "name": "...", "venue": "..." }
    final location = map['location'] as Map<String, dynamic>?;
    final locationName = map['location_name'] as String?
        ?? location?['name'] as String?
        ?? location?['venue'] as String?;

    // media is a jsonb column: { "thumbnail": "...", "poster": "..." }
    final media = map['media'] as Map<String, dynamic>?;
    final thumbnailUrl = map['thumbnail_url'] as String?
        ?? map['event_thumbnail_url'] as String?
        ?? media?['thumbnail'] as String?
        ?? media?['poster'] as String?;

    return EventModel(
      id: (map['event_id'] ?? map['id']) as String,
      title: (map['event_title'] ?? map['title']) as String,
      description: map['description'] as String? ?? '',
      startDatetime: DateTime.parse(startRaw as String),
      endDatetime: DateTime.parse(endRaw as String),
      timezone: map['timezone'] as String?,
      locationName: locationName,
      thumbnailUrl: thumbnailUrl,
      category: map['category_name'] as String?,
      categoryId: map['category_id'] as String?,
      status: map['status'] as String?,
      isPrivate: map['is_private'] as bool? ?? false,
      isOnline: map['is_online'] as bool? ?? false,
      currency: map['currency'] as String?,
      totalCapacity: map['total_capacity'] as int?,
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
        timezone,
        locationName,
        thumbnailUrl,
        category,
        categoryId,
        status,
        isPrivate,
        isOnline,
        currency,
        totalCapacity,
        chatCount,
      ];
}
