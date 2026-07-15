/// Maps event.timezone (an IANA name, e.g. "Africa/Nairobi") to a short
/// display abbreviation (e.g. "EAT"). Covers Sub-Saharan Africa, the app's
/// primary market, plus a few globally-common zones; falls back to the raw
/// UTC offset for anything unmapped rather than a full IANA tzdata lookup.
class TimezoneAbbreviation {
  static const Map<String, String> _abbreviations = {
    'Africa/Nairobi': 'EAT',
    'Africa/Kampala': 'EAT',
    'Africa/Dar_es_Salaam': 'EAT',
    'Africa/Addis_Ababa': 'EAT',
    'Africa/Mogadishu': 'EAT',
    'Africa/Kigali': 'CAT',
    'Africa/Lagos': 'WAT',
    'Africa/Accra': 'GMT',
    'Africa/Abidjan': 'GMT',
    'Africa/Dakar': 'GMT',
    'Africa/Johannesburg': 'SAST',
    'Africa/Harare': 'CAT',
    'Africa/Lusaka': 'CAT',
    'Africa/Cairo': 'EET',
    'Africa/Casablanca': 'WET',
    'Europe/London': 'GMT',
    'Europe/Paris': 'CET',
    'America/New_York': 'ET',
    'America/Los_Angeles': 'PT',
    'Asia/Dubai': 'GST',
    'UTC': 'UTC',
  };

  /// Returns a short abbreviation for [ianaName] (e.g. "Africa/Nairobi" ->
  /// "EAT"), or null if [ianaName] is null/empty and there's nothing to show.
  static String? forIana(String? ianaName) {
    if (ianaName == null || ianaName.isEmpty) return null;
    return _abbreviations[ianaName] ?? ianaName.split('/').last.replaceAll('_', ' ');
  }
}
