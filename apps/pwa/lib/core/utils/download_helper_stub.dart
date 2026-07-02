import 'package:url_launcher/url_launcher.dart';

class DownloadResult {
  final bool downloaded;
  final bool openedInNewTab;
  const DownloadResult({required this.downloaded, required this.openedInNewTab});
}

// Non-web platforms (native mobile/desktop): url_launcher's externalApplication
// mode hands the URL to the OS, which downloads/opens it via the platform's
// own file/media handling — there is no "new tab" concept off the web, so
// this path is unaffected by the web download bug.
Future<DownloadResult> downloadFile(String url, String filename) async {
  final uri = Uri.tryParse(url);
  if (uri == null) throw Exception('Invalid URL');
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw Exception('Could not open download link');
    }
    return const DownloadResult(downloaded: true, openedInNewTab: false);
  } catch (e) {
    throw Exception('Failed to initiate download: $e');
  }
}
