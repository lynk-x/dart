import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS('window.flutterQrScanner.start')
external JSPromise<JSBoolean> _jsStart(JSString videoElementId, JSFunction onScanCallback);

@JS('window.flutterQrScanner.stop')
external void _jsStop();

class WebQrScanner extends StatefulWidget {
  final void Function(String) onDetect;

  const WebQrScanner({
    super.key,
    required this.onDetect,
  });

  @override
  State<WebQrScanner> createState() => _WebQrScannerState();
}

class _WebQrScannerState extends State<WebQrScanner> {
  static const String _viewType = 'qr-video-view';
  static const String _elementId = 'qr-video-element';
  bool _isInitialized = false;
  bool _checkingPermission = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    // Register the platform view factory
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        final video = web.HTMLVideoElement()
          ..id = _elementId
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover';
        
        video.setAttribute('playsinline', 'true');
        video.setAttribute('autoplay', 'true');
        video.setAttribute('muted', 'true');
        
        return video;
      },
    );

    // Start the camera after the platform view has been inserted into the DOM
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScanner();
    });
  }

  Future<void> _startScanner() async {
    if (!mounted) return;
    setState(() {
      _checkingPermission = true;
      _errorMessage = null;
    });

    try {
      final jsCallback = (JSString code) {
        widget.onDetect(code.toDart);
      }.toJS;

      final promise = _jsStart(_elementId.toJS, jsCallback);
      final result = await promise.toDart;
      
      if (mounted) {
        setState(() {
          _isInitialized = result.toDart;
          _checkingPermission = false;
          if (!_isInitialized) {
            _errorMessage = 'Camera access was denied or no camera was found. Please check your browser permissions.';
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to start web QR scanner: $e');
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _checkingPermission = false;
          _errorMessage = 'Error initializing camera: ${e.toString()}';
        });
      }
    }
  }

  @override
  void dispose() {
    try {
      _jsStop();
    } catch (e) {
      debugPrint('Failed to stop web QR scanner: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const HtmlElementView(viewType: _viewType),
        if (!_isInitialized)
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Center(
              child: _checkingPermission
                  ? const CircularProgressIndicator(
                      color: Color(0xFF20F928),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.videocam_off_rounded,
                          color: Colors.white38,
                          size: 44,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Camera Access Required',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Inter',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _errorMessage ?? 'Please grant camera permission to scan tickets.',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontFamily: 'Inter',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _startScanner,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Grant Permission / Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF20F928),
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
      ],
    );
  }
}
