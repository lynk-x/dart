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
  final double? purchasedPrice;
  final String? purchasedCurrency;

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
    this.purchasedPrice,
    this.purchasedCurrency,
  });

  factory TicketModel.fromMap(Map<String, dynamic> map,
      {required String holderName}) {
    final event = map['events'] as Map<String, dynamic>;
    final tier = map['ticket_tiers'] as Map<String, dynamic>;
    // location and media are jsonb columns on public.events
    final location = event['location'] as Map<String, dynamic>?;
    final media = event['media'] as Map<String, dynamic>?;
    // status enum: active | used | cancelled | expired | transferred
    final ticketStatus = map['status'] as String? ?? 'active';

    return TicketModel(
      id: map['id'] as String,
      eventId: map['event_id'] as String,
      eventTitle: event['title'] as String,
      locationName: location?['venue'] as String?
          ?? location?['name'] as String?
          ?? 'Online',
      startsAt: DateTime.parse(event['starts_at'] as String),
      endsAt: DateTime.parse(event['ends_at'] as String),
      thumbnailUrl: media?['thumbnail'] as String?
          ?? media?['poster'] as String?
          ?? media?['hero'] as String?,
      tierName: tier['display_name'] as String,
      // Schema column is 'code', not 'ticket_code'
      ticketCode: map['ticket_code'] as String,
      status: ticketStatus,
      isRedeemed: ticketStatus == 'used',
      redeemedAt: null,
      holderName: holderName,
      purchasedPrice: (map['purchased_price'] as num?)?.toDouble(),
      purchasedCurrency: map['purchased_currency'] as String?,
    );
  }
}
