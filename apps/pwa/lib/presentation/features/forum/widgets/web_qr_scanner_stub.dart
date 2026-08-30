import 'package:flutter/material.dart';

class WebQrScanner extends StatelessWidget {
  final void Function(String) onDetect;
  final void Function(String)? onError;
  final bool torchEnabled;

  const WebQrScanner({
    super.key,
    required this.onDetect,
    this.onError,
    this.torchEnabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Web QR Scanner is not supported on this platform.'),
    );
  }
}

Future<bool> switchWebCamera() async {
  return false;
}

Future<bool> toggleWebTorch(bool enabled) async {
  return false;
}

void setWebScanInterval(int ms) {}

void resumeWebScanner() {}

