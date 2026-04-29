class Country {
  final String name;
  final String code;
  const Country({required this.name, required this.code});
}

const List<Country> kSupportedCountries = [
  Country(name: 'Kenya', code: 'KE'),
  Country(name: 'Uganda', code: 'UG'),
  Country(name: 'Tanzania', code: 'TZ'),
  Country(name: 'Rwanda', code: 'RW'),
  Country(name: 'Nigeria', code: 'NG'),
  Country(name: 'South Africa', code: 'ZA'),
  Country(name: 'United States', code: 'US'),
  Country(name: 'United Kingdom', code: 'GB'),
  Country(name: 'Global', code: 'GL'),
];
