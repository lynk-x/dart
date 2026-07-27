import 'package:flutter/material.dart';

void revokeWebCameraCaptureUrl(String url) {}

class WebCameraCaptureResult {
  final String objectUrl;
  final bool isVideo;
  final bool openGallery;

  const WebCameraCaptureResult({required this.objectUrl, required this.isVideo})
      : openGallery = false;

  const WebCameraCaptureResult.openGallery()
      : objectUrl = '',
        isVideo = false,
        openGallery = true;
}

class WebCameraCaptureScreen extends StatelessWidget {
  const WebCameraCaptureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'Camera capture is not supported on this platform.',
          style: TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}
