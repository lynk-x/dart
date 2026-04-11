class TicketModel {
  final String id;
  final String eventId;
  final String eventTitle;
  final String locationName;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? thumbnailUrl;
  final String tierName;
  final String ticketCode;
  final String status;
  final bool isRedeemed;
  final DateTime? redeemedAt;
  final String holderName;

  TicketModel({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.locationName,
    required this.startsAt,
    required this.endsAt,
    this.thumbnailUrl,
    required this.tierName,
    required this.ticketCode,
    required this.status,
    required this.isRedeemed,
    this.redeemedAt,
    required this.holderName,
  });

  factory TicketModel.fromMap(Map<String, dynamic> map,
      {required String holderName}) {
    final event = map['events'] as Map<String, dynamic>;
    final tier = map['ticket_tiers'] as Map<String, dynamic>;
    final location = event['location'] as Map<String, dynamic>?;
    final media = event['media'] as Map<String, dynamic>?;

    return TicketModel(
      id: map['id'] as String,
      eventId: map['event_id'] as String,
      eventTitle: event['title'] as String,
      locationName: location?['venue'] as String? ?? 'Online',
      startsAt: DateTime.parse(event['starts_at'] as String),
      endsAt: DateTime.parse(event['ends_at'] as String),
      thumbnailUrl: media?['poster'] as String? ?? media?['hero'] as String?,
      tierName: tier['display_name'] as String,
      ticketCode: map['ticket_code'] as String,
      status: map['status'] as String,
      isRedeemed: map['redeemed_at'] != null,
      redeemedAt: map['redeemed_at'] != null
          ? DateTime.parse(map['redeemed_at'] as String)
          : null,
      holderName: holderName,
    );
  }
}
