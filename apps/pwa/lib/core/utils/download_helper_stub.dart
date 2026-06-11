import 'package:url_launcher/url_launcher.dart';

Future<void> downloadFile(String url, String filename) async {
  final uri = Uri.tryParse(url);
  if (uri == null) throw Exception('Invalid URL');
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw Exception('Could not open download link');
    }
  } catch (e) {
    throw Exception('Failed to initiate download: $e');
  }
}
