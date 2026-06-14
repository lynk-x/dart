import 'package:equatable/equatable.dart';

/// Represents a single session within a forum.
class SessionModel extends Equatable {
  final String id;
  final String forumId;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final int sortOrder;
  final List<String> speakers;
  final String? room;
  final int? capacity;
  final DateTime? forumCreatedAt;

  const SessionModel({
    required this.id,
    required this.forumId,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.sortOrder = 0,
    this.speakers = const [],
    this.room,
    this.capacity,
    this.forumCreatedAt,
  });

  factory SessionModel.fromMap(Map<String, dynamic> map) {
    final info = map['info'] as Map<String, dynamic>? ?? {};
    final speakersRaw = info['speakers'];
    List<String> speakers = [];
    if (speakersRaw is List) {
      speakers = speakersRaw.map((e) => e.toString()).toList();
    }

    final forumCreatedAtRaw = map['forum_created_at'];

    return SessionModel(
      id: map['id'] as String,
      forumId: map['forum_id'] as String,
      title: info['title'] as String? ?? 'Untitled Session',
      startsAt: DateTime.parse(map['starts_at'] as String).toLocal(),
      endsAt: DateTime.parse(map['ends_at'] as String).toLocal(),
      sortOrder: map['sort_order'] as int? ?? 0,
      speakers: speakers,
      room: info['room'] as String?,
      capacity: info['capacity'] as int?,
      forumCreatedAt: forumCreatedAtRaw != null ? DateTime.parse(forumCreatedAtRaw as String).toLocal() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'forum_id': forumId,
      'forum_created_at': forumCreatedAt?.toUtc().toIso8601String(),
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'sort_order': sortOrder,
      'info': {
        'title': title,
        'speakers': speakers,
        'room': room,
        'capacity': capacity,
      },
    };
  }

  @override
  List<Object?> get props => [
        id,
        forumId,
        title,
        startsAt,
        endsAt,
        sortOrder,
        speakers,
        room,
        capacity,
        forumCreatedAt,
      ];
}
