import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// True on Safari/WebKit, which does not reliably honor the `download`
/// attribute on `<a>` elements pointing at `blob:` URLs — clicking such a
/// link often navigates to/renders the blob instead of saving it (WebKit bug
/// 190351, still present as of Safari 17/18). There is no fully reliable
/// pure-JS workaround, so on Safari we fall back to opening the original
/// (non-blob) URL in a new tab and let the user save it manually, rather than
/// silently failing to download while claiming success.
bool get _isSafari {
  final ua = web.window.navigator.userAgent.toLowerCase();
  return ua.contains('safari') && !ua.contains('chrome') && !ua.contains('crios') && !ua.contains('android');
}

class DownloadResult {
  final bool downloaded;
  final bool openedInNewTab;
  const DownloadResult({required this.downloaded, required this.openedInNewTab});
}

Future<DownloadResult> downloadFile(String url, String filename) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return const DownloadResult(downloaded: false, openedInNewTab: false);

  if (_isSafari) {
    web.window.open(url, '_blank');
    return const DownloadResult(downloaded: false, openedInNewTab: true);
  }

  try {
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final bytes = Uint8List.fromList(response.bodyBytes);
      final blob = web.Blob(
        [bytes.toJS].toJS,
        web.BlobPropertyBag(type: 'application/octet-stream'),
      );
      final blobUrl = web.URL.createObjectURL(blob);
      final anchor = web.HTMLAnchorElement()
        ..href = blobUrl
        ..download = filename
        ..style.display = 'none';
      web.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      web.URL.revokeObjectURL(blobUrl);
      return const DownloadResult(downloaded: true, openedInNewTab: false);
    } else {
      throw Exception('Server returned status code ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('[DownloadHelper] Web download failed: $e');
    rethrow;
  }
}
