import 'package:flutter/material.dart';

class WebCameraCaptureResult {
  final String objectUrl;
  final bool isVideo;

  const WebCameraCaptureResult({required this.objectUrl, required this.isVideo});
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
