import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS('window.flutterQrScanner.start')
external JSPromise<JSBoolean> _jsStart(JSString videoElementId, JSFunction onScanCallback);

@JS('window.flutterQrScanner.stop')
external void _jsStop();

@JS('window.flutterQrScanner.toggleTorch')
external JSPromise<JSBoolean> _jsToggleTorch(JSBoolean enabled);

@JS('window.flutterQrScanner.switchCamera')
external JSPromise<JSBoolean> _jsSwitchCamera();

@JS('window.flutterQrScanner.setScanInterval')
external void _jsSetScanInterval(JSNumber ms);

void setWebScanInterval(int ms) {
  try {
    _jsSetScanInterval(ms.toJS);
  } catch (e) {
    debugPrint('Failed to set web scan interval: $e');
  }
}

Future<bool> switchWebCamera() async {
  try {
    final result = await _jsSwitchCamera().toDart;
    return result.toDart;
  } catch (e) {
    debugPrint('Failed to switch web camera: $e');
    return false;
  }
}

Future<bool> toggleWebTorch(bool enabled) async {
  try {
    final result = await _jsToggleTorch(enabled.toJS).toDart;
    return result.toDart;
  } catch (e) {
    debugPrint('Failed to toggle web torch: $e');
    return false;
  }
}

class WebQrScanner extends StatefulWidget {
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
  State<WebQrScanner> createState() => _WebQrScannerState();
}

class _WebQrScannerState extends State<WebQrScanner> {
  static const String _viewType = 'qr-video-view';
  static const String _elementId = 'qr-video-element';
  static web.HTMLVideoElement? _cachedVideo;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();

    if (_cachedVideo == null) {
      _cachedVideo = web.HTMLVideoElement()
        ..id = _elementId
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover';
      
      _cachedVideo!.setAttribute('playsinline', 'true');
      _cachedVideo!.setAttribute('autoplay', 'true');
      _cachedVideo!.setAttribute('muted', 'true');
    }

    // Register the platform view factory to return our single cached video element
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _cachedVideo!,
    );

    // Start the camera after the platform view has been inserted into the DOM
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScanner();
    });
  }

  Future<void> _startScanner() async {
    try {
      final jsCallback = (JSString code) {
        widget.onDetect(code.toDart);
      }.toJS;

      final promise = _jsStart(_elementId.toJS, jsCallback);
      final result = await promise.toDart;
      
      if (mounted) {
        setState(() {
          _isInitialized = result.toDart;
        });
        if (!result.toDart) {
          widget.onError?.call('Could not access camera or initialize stream. Please verify permissions.');
        } else if (widget.torchEnabled) {
          _setTorch(true);
        }
      }
    } catch (e) {
      debugPrint('Failed to start web QR scanner: $e');
      widget.onError?.call(e.toString());
    }
  }

  @override
  void didUpdateWidget(WebQrScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.torchEnabled != widget.torchEnabled && _isInitialized) {
      _setTorch(widget.torchEnabled);
    }
  }

  Future<void> _setTorch(bool enabled) async {
    try {
      await _jsToggleTorch(enabled.toJS).toDart;
    } catch (e) {
      debugPrint('Failed to toggle web torch: $e');
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
            child: const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF20F928),
              ),
            ),
          ),
      ],
    );
  }
}
