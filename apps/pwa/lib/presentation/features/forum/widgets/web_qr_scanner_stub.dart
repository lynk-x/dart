import 'package:flutter/material.dart';

class WebQrScanner extends StatelessWidget {
  final void Function(String) onDetect;
  final bool torchEnabled;

  const WebQrScanner({
    super.key,
    required this.onDetect,
    this.torchEnabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Web QR Scanner is not supported on this platform.'),
    );
  }
}
