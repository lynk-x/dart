// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

Future<void> downloadFile(String url, String filename) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final blob = html.Blob([response.bodyBytes]);
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: blobUrl)
        ..setAttribute("download", filename)
        ..style.display = 'none';
      html.document.body?.children.add(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(blobUrl);
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    debugPrint('[DownloadHelper] Web download failed: $e');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
