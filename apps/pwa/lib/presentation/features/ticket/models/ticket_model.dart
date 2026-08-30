class TicketModel {
  final String id;
  final String reference;
  final String eventId;
  final String eventTitle;
  final String locationName;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? timezone;
  final String? thumbnailUrl;
  final String tierName;
  final String ticketCode;
  final String status;
  final bool isRedeemed;
  final DateTime? redeemedAt;
  final String holderName;
  final double? purchasedPrice;
  final String? purchasedCurrency;
  final String? secretKey;

  TicketModel({
    required this.id,
    required this.reference,
    required this.eventId,
    required this.eventTitle,
    required this.locationName,
    required this.startsAt,
    required this.endsAt,
    this.timezone,
    this.thumbnailUrl,
    required this.tierName,
    required this.ticketCode,
    required this.status,
    required this.isRedeemed,
    this.redeemedAt,
    required this.holderName,
    this.purchasedPrice,
    this.purchasedCurrency,
    this.secretKey,
  });

  /// Formats any raw code/reference or UUID into a clean human-readable ticket code.
  static String formatCleanReference(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'TKT-000000';
    final trimmed = raw.trim().replaceAll(RegExp(r'^#'), '');
    final cleanNoHyphen = trimmed.replaceAll('-', '');
    final isUuid = cleanNoHyphen.length == 32 &&
        RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(cleanNoHyphen);

    if (isUuid) {
      return 'TKT-${cleanNoHyphen.substring(0, 8).toUpperCase()}';
    }
    return trimmed;
  }

  /// Returns a clean human-readable ticket reference code (never a raw 36-char UUID).
  String get displayCode {
    if (reference.trim().isNotEmpty) {
      return formatCleanReference(reference);
    }
    return formatCleanReference(ticketCode);
  }

  static String _parseLocation(dynamic locationRaw, [dynamic venueNameRaw]) {
    if (venueNameRaw is String && venueNameRaw.trim().isNotEmpty) {
      return venueNameRaw.trim();
    }
    if (locationRaw is String && locationRaw.trim().isNotEmpty) {
      return locationRaw.trim();
    }
    if (locationRaw is Map) {
      final venue = locationRaw['venue'] as String? ??
          locationRaw['name'] as String? ??
          locationRaw['title'] as String? ??
          locationRaw['city'] as String? ??
          locationRaw['address'] as String?;
      if (venue != null && venue.trim().isNotEmpty) {
        return venue.trim();
      }
    }
    return 'TBD';
  }

  factory TicketModel.fromMap(Map<String, dynamic> map,
      {required String holderName}) {
    final event = map['events'] as Map<String, dynamic>;
    final tier = map['ticket_tiers'] as Map<String, dynamic>;
    // location and media are jsonb columns on public.events
    final media = event['media'] as Map<String, dynamic>?;
    // status enum: active | used | cancelled | expired | transferred
    final ticketStatus = map['status'] as String? ?? 'active';

    return TicketModel(
      id: map['id'] as String,
      reference: formatCleanReference(map['reference']?.toString() ?? map['ticket_code']?.toString()),
      eventId: map['event_id'] as String,
      eventTitle: event['title'] as String,
      locationName: _parseLocation(event['location'], event['venue_name'] ?? event['venue']),
      startsAt: DateTime.parse(event['starts_at'] as String),
      endsAt: DateTime.parse(event['ends_at'] as String),
      timezone: event['timezone'] as String?,
      thumbnailUrl: media?['thumbnail'] as String?
          ?? media?['poster'] as String?
          ?? media?['hero'] as String?,
      tierName: tier['display_name'] as String,
      ticketCode: formatCleanReference(map['ticket_code']?.toString() ?? map['reference']?.toString()),
      status: ticketStatus,
      isRedeemed: ticketStatus == 'used',
      redeemedAt: map['redeemed_at'] != null ? DateTime.parse(map['redeemed_at'] as String) : null,
      holderName: holderName,
      purchasedPrice: (map['purchased_price'] as num?)?.toDouble(),
      purchasedCurrency: map['purchased_currency'] as String?,
      secretKey: map['secret_key'] as String?,
    );
  }

  factory TicketModel.fromView(Map<String, dynamic> map) {
    final ticketStatus = map['status'] as String? ?? 'active';
    return TicketModel(
      id: map['ticket_id'] as String,
      reference: formatCleanReference(map['reference']?.toString() ?? map['ticket_code']?.toString()),
      eventId: map['event_id'] as String,
      eventTitle: map['event_title'] as String,
      locationName: _parseLocation(
        map['location'] ?? map['location_name'] ?? map['venue'],
        map['venue_name'] ?? map['event_venue'],
      ),
      startsAt: DateTime.parse(map['starts_at'] as String),
      endsAt: DateTime.parse(map['ends_at'] as String),
      timezone: map['timezone'] as String?,
      thumbnailUrl: map['thumbnail_url'] as String?,
      tierName: map['tier_name'] as String,
      ticketCode: formatCleanReference(map['ticket_code']?.toString() ?? map['reference']?.toString()),
      status: ticketStatus,
      isRedeemed: ticketStatus == 'used',
      redeemedAt: map['redeemed_at'] != null ? DateTime.parse(map['redeemed_at'] as String) : null,
      holderName: map['holder_name'] as String? ?? 'Guest Attendee',
      purchasedPrice: (map['purchased_price'] as num?)?.toDouble(),
      purchasedCurrency: map['purchased_currency'] as String?,
      secretKey: map['secret_key'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ticket_id': id,
      'reference': reference,
      'event_id': eventId,
      'event_title': eventTitle,
      'venue_name': locationName,
      'starts_at': startsAt.toIso8601String(),
      'ends_at': endsAt.toIso8601String(),
      'timezone': timezone,
      'thumbnail_url': thumbnailUrl,
      'tier_name': tierName,
      'ticket_code': ticketCode,
      'status': status,
      'redeemed_at': redeemedAt?.toIso8601String(),
      'holder_name': holderName,
      'purchased_price': purchasedPrice,
      'purchased_currency': purchasedCurrency,
      'secret_key': secretKey,
    };
  }
}
