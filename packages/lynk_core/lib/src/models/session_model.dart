import 'package:equatable/equatable.dart';

/// Represents a single session within an event.
class SessionModel extends Equatable {
  final String id;
  final String eventId;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final int sortOrder;
  final List<String> speakers;
  final String? room;
  final int? capacity;

  const SessionModel({
    required this.id,
    required this.eventId,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.sortOrder = 0,
    this.speakers = const [],
    this.room,
    this.capacity,
  });

  factory SessionModel.fromMap(Map<String, dynamic> map) {
    final info = map['info'] as Map<String, dynamic>? ?? {};
    final speakersRaw = info['speakers'];
    List<String> speakers = [];
    if (speakersRaw is List) {
      speakers = speakersRaw.map((e) => e.toString()).toList();
    }

    return SessionModel(
      id: map['id'] as String,
      eventId: map['event_id'] as String,
      title: info['title'] as String? ?? 'Untitled Session',
      startsAt: DateTime.parse(map['starts_at'] as String),
      endsAt: DateTime.parse(map['ends_at'] as String),
      sortOrder: map['sort_order'] as int? ?? 0,
      speakers: speakers,
      room: info['room'] as String?,
      capacity: info['capacity'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'event_id': eventId,
      'starts_at': startsAt.toIso8601String(),
      'ends_at': endsAt.toIso8601String(),
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
        eventId,
        title,
        startsAt,
        endsAt,
        sortOrder,
        speakers,
        room,
        capacity,
      ];
}
