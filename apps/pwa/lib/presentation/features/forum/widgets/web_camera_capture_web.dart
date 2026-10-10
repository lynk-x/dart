import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import 'package:lynk_x/presentation/shared/utils/permission_acks.dart';
import 'web_camera_capture_widgets.dart';
export 'web_camera_capture_widgets.dart' show WebCameraCaptureResult;

@JS('window.flutterCameraStream.start')
external JSPromise<JSBoolean> _jsStart(JSString videoElementId, JSString facingMode);

@JS('window.flutterCameraStream.stop')
external void _jsStop();

@JS('window.flutterCameraStream.switchCamera')
external JSPromise<JSBoolean> _jsSwitchCamera();

@JS('window.flutterCameraStream.capturePhoto')
external JSPromise<JSString?> _jsCapturePhoto();

@JS('window.flutterCameraStream.startRecording')
external JSPromise<JSBoolean> _jsStartRecording();

@JS('window.flutterCameraStream.stopRecording')
external JSPromise<JSString?> _jsStopRecording();

@JS('window.flutterCameraStream.toggleTorch')
external JSPromise<JSBoolean> _jsToggleTorch(JSBoolean enabled);

@JS('window.flutterCameraStream.revokeObjectUrl')
external void _jsRevokeObjectUrl(JSString url);

@JS('window.flutterCameraStream.isFrontFacing')
external JSBoolean _jsIsFrontFacing();

@JS('window.flutterCameraStream.getZoomCapabilities')
external JSObject? _jsGetZoomCapabilities();

@JS('window.flutterCameraStream.setZoom')
external JSPromise<JSBoolean> _jsSetZoom(JSNumber value);

/// Releases a capture screen's blob URL from browser memory once the
/// caller (e.g. media_tab.dart, after uploadMultipleMedia has read its
/// bytes) no longer needs it. Safe to call more than once for the same URL.
void revokeWebCameraCaptureUrl(String url) {
  try {
    _jsRevokeObjectUrl(url.toJS);
  } catch (_) {}
}


class WebCameraCaptureScreen extends StatefulWidget {
  const WebCameraCaptureScreen({super.key});

  @override
  State<WebCameraCaptureScreen> createState() => _WebCameraCaptureScreenState();
}

class _WebCameraCaptureScreenState extends State<WebCameraCaptureScreen> {
  static const String _viewType = 'camera-capture-video-view';
  static const String _elementId = 'camera-capture-video-element';
  static web.HTMLVideoElement? _cachedVideo;
  static const int maxRecordSeconds = 30;

  bool _isInitialized = false;
  bool _isVideoMode = false;
  bool _isRecording = false;
  bool _isBusy = false;
  bool _torchEnabled = false;
  Timer? _recordTimer;
  int _recordSeconds = 0;
  String? _error;

  // Set once a photo/video has been captured, switching the screen into a
  // review state (Retake / Use) instead of uploading immediately — a bad
  // take (blocked framing, motion blur, wrong mode) should be catchable
  // before it's sent, not only after via delete/report.
  WebCameraCaptureResult? _pendingResult;
  VideoPlayerController? _reviewVideoController;

  // Non-empty while reviewing a gallery pick — a grid (not the single-item
  // Retake/Use flow above) since FileType.media allows multi-select and
  // mixed image/video types in one pick.
  List<PickedMediaItem> _pickedGalleryItems = [];

  // Null when the active camera doesn't report a zoom capability (common on
  // desktop webcams, Firefox, and some Android builds) — the pinch gesture
  // simply does nothing in that case rather than showing a dead control.
  double? _zoomMin;
  double? _zoomMax;
  double _currentZoom = 1.0;
  double _pinchStartZoom = 1.0;
  bool _isPinching = false;
  Timer? _zoomHideTimer;

  void _refreshZoomCapabilities() {
    final caps = _jsGetZoomCapabilities();
    if (caps == null) {
      _zoomMin = null;
      _zoomMax = null;
      return;
    }
    final map = (caps as JSAny).dartify() as Map?;
    if (map == null) {
      _zoomMin = null;
      _zoomMax = null;
      return;
    }
    _zoomMin = (map['min'] as num?)?.toDouble();
    _zoomMax = (map['max'] as num?)?.toDouble();
    _currentZoom = _zoomMin ?? 1.0;
  }

  bool get _zoomSupported => _zoomMin != null && _zoomMax != null && _zoomMax! > _zoomMin!;

  int _lastZoomConstraintTimeMs = 0;

  void _onScaleStart(ScaleStartDetails details) {
    _pinchStartZoom = _currentZoom;
    _zoomHideTimer?.cancel();
    if (_zoomSupported && !_isPinching) {
      _isPinching = true;
      if (mounted) setState(() {});
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_zoomSupported || _isBusy) return;
    final min = _zoomMin!;
    final max = _zoomMax!;
    final next = (_pinchStartZoom * details.scale).clamp(min, max);
    if ((next - _currentZoom).abs() < 0.02) return;
    _currentZoom = next;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastZoomConstraintTimeMs > 50) {
      _lastZoomConstraintTimeMs = now;
      _jsSetZoom(next.toJS);
    }
    if (mounted) setState(() {});
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _zoomHideTimer?.cancel();
    _zoomHideTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted && _isPinching) {
        setState(() {
          _isPinching = false;
        });
      }
    });
  }

  // Preview-layer CSS transform on the <video> element — matches the "mirror"
  // convention every native camera app uses for the front camera (shows what
  // you'd see in a mirror). capturePhoto() mirrors front-facing captured photos
  // in JS so what you see in the live view matches the captured image.
  void _applyMirrorTransform() {
    final isFront = _jsIsFrontFacing().toDart;
    _cachedVideo?.style.transform = isFront ? 'scaleX(-1)' : 'none';
  }

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
    } else {
      _cachedVideo!.style.objectFit = 'cover';
    }

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _cachedVideo!,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCamera();
    });
  }

  Future<void> _startCamera() async {
    try {
      final result = await _jsStart(_elementId.toJS, 'environment'.toJS).toDart;
      if (!mounted) return;
      if (result.toDart) {
        _applyMirrorTransform();
        _refreshZoomCapabilities();
      }
      setState(() {
        _isInitialized = result.toDart;
        if (!result.toDart) {
          _error = 'Could not access camera. Please check permissions.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not access camera: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_isRecording) return;
    try {
      final switched = (await _jsSwitchCamera().toDart).toDart;
      if (switched) {
        _applyMirrorTransform();
        _refreshZoomCapabilities();
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _toggleTorch() async {
    final next = !_torchEnabled;
    bool success = false;
    try {
      success = (await _jsToggleTorch(next.toJS).toDart).toDart;
    } catch (_) {}

    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).clearSnackBars();
      AppSnackBars.showError(context, 'Flashlight is not supported on this device/browser');
      return;
    }
    setState(() => _torchEnabled = next);
  }

  void _setMode(bool video) {
    if (_isRecording) return;
    setState(() => _isVideoMode = video);
  }

  // Opens the same FileType.media picker as media_tab.dart's standalone
  // Upload Media button, without leaving this screen — canceling the
  // picker leaves the live camera preview running, ready to shoot.
  // Selecting files pops this screen with them, which media_tab.dart
  // uploads through the same path as any other gallery pick.
  Future<void> _openGallery() async {
    await PermissionAcks.ensureAcknowledged(
      context,
      PermissionAckType.media,
      title: 'Access your Media',
      description:
          'To share photos and videos with the forum, we need access to your device library.',
      icon: Icons.perm_media_rounded,
      actionLabel: 'Allow Access',
      onReady: () {
        if (mounted) _actuallyOpenGallery();
      },
    );
  }

  Future<void> _actuallyOpenGallery() async {
    try {
      // image_picker rather than file_picker: file_picker's FileType.media
      // sets accept="video/*|image/*" on the underlying <input type="file">
      // web element — pipe-separated, which isn't valid HTML accept syntax
      // (the spec requires commas). Browsers silently ignore the malformed
      // filter and fall back to a generic file browser instead of the
      // native Photos/Gallery picker. image_picker's getMedia() uses the
      // correct "image/*,video/*" and is what the old per-type Upload
      // buttons used before this screen existed.
      final files = await ImagePicker().pickMultipleMedia();
      if (files.isEmpty || !mounted) return;

      final items = <PickedMediaItem>[];
      for (final file in files) {
        final bytes = await file.readAsBytes();
        items.add(PickedMediaItem(file: file, bytes: bytes));
      }
      if (items.isEmpty || !mounted) return;

      setState(() => _pickedGalleryItems = items);
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.showError(context, 'Could not access your media library.');
    }
  }

  void _removePickedGalleryItem(PickedMediaItem item) {
    setState(() {
      _pickedGalleryItems = _pickedGalleryItems.where((i) => i != item).toList();
    });
  }

  void _usePickedGalleryItems() {
    final files = [for (final item in _pickedGalleryItems) item.file];
    Navigator.of(context).pop(WebCameraCaptureResult.pickedFiles(files));
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isBusy || !_isInitialized) return;

    await PermissionAcks.ensureAcknowledged(
      context,
      PermissionAckType.microphone,
      title: 'Microphone Access Needed',
      description:
          'To record video clips with audio, Lynk-X needs access to your microphone.',
      icon: Icons.mic_rounded,
      actionLabel: 'Allow Microphone',
      onReady: () => _actuallyStartRecording(),
    );
  }

  Future<void> _actuallyStartRecording() async {
    if (!mounted || _isRecording || _isBusy || !_isInitialized) return;

    final started = (await _jsStartRecording().toDart).toDart;
    if (!started) {
      setState(() => _error = 'Failed to start recording.');
      return;
    }

    setState(() {
      _isRecording = true;
      _recordSeconds = 0;
    });
    _recordTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      if (_recordSeconds >= maxRecordSeconds * 10 - 1) {
        _stopRecording();
        return;
      }
      setState(() => _recordSeconds++);
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    setState(() {
      _isBusy = true;
      _isRecording = false;
    });
    try {
      final result = await _jsStopRecording().toDart;
      final url = result?.toDart;
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        setState(() {
          _isBusy = false;
          _error = 'Failed to save recording.';
        });
        return;
      }
      await _prepareVideoReview(url);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _error = 'Failed to save recording: $e';
      });
    }
  }

  Future<void> _onShutterTap() async {
    if (_isBusy || !_isInitialized) return;

    if (!_isVideoMode) {
      setState(() => _isBusy = true);
      try {
        final result = await _jsCapturePhoto().toDart;
        final url = result?.toDart;
        if (!mounted) return;
        if (url == null || url.isEmpty) {
          setState(() => _isBusy = false);
          AppSnackBars.showError(context, 'Failed to capture photo.');
          return;
        }
        _cachedVideo?.style.display = 'none';
        setState(() {
          _isBusy = false;
          _pendingResult = WebCameraCaptureResult(objectUrl: url, isVideo: false);
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _isBusy = false);
        AppSnackBars.showError(context, 'Failed to capture photo: $e');
      }
      return;
    }

    if (!_isRecording) {
      await _startRecording();
    } else {
      await _stopRecording();
    }
  }

  Future<void> _onShutterLongPress() async {
    if (_isBusy || !_isInitialized || _isRecording) return;

    if (!_isVideoMode) {
      setState(() => _isVideoMode = true);
    }
    await _startRecording();
  }

  Future<void> _prepareVideoReview(String url) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.setLooping(true);
      try {
        await controller.play();
      } catch (_) {
        controller.setVolume(0);
        await controller.play();
      }
      _cachedVideo?.style.display = 'none';
      setState(() {
        _isBusy = false;
        _reviewVideoController = controller;
        _pendingResult = WebCameraCaptureResult(objectUrl: url, isVideo: true);
      });
    } catch (e) {
      try {
        _jsRevokeObjectUrl(url.toJS);
      } catch (_) {}
      controller.dispose();
      if (!mounted) return;
      setState(() => _isBusy = false);
      AppSnackBars.showError(context, 'Failed to load video recording: $e');
    }
  }

  // Discards the pending capture and returns to the live camera preview.
  // The stream itself is never stopped/restarted here — only started once
  // in initState and stopped once in dispose — so retaking is instant.
  void _retake() {
    if (_pendingResult != null && _pendingResult!.objectUrl.isNotEmpty) {
      try {
        _jsRevokeObjectUrl(_pendingResult!.objectUrl.toJS);
      } catch (_) {}
    }
    _reviewVideoController?.dispose();
    _cachedVideo?.style.display = 'block';
    setState(() {
      _pendingResult = null;
      _reviewVideoController = null;
    });
  }

  void _useCapture([bool isMuted = false]) {
    _cachedVideo?.style.display = 'block';
    final finalResult = _pendingResult != null && _pendingResult!.isVideo
        ? WebCameraCaptureResult(
            objectUrl: _pendingResult!.objectUrl,
            isVideo: true,
            isMuted: isMuted,
          )
        : _pendingResult;
    Navigator.of(context).pop(finalResult);
  }

  @override
  void dispose() {
    _zoomHideTimer?.cancel();
    _recordTimer?.cancel();
    if (_pendingResult != null && _pendingResult!.objectUrl.isNotEmpty) {
      try {
        _jsRevokeObjectUrl(_pendingResult!.objectUrl.toJS);
      } catch (_) {}
    }
    _reviewVideoController?.dispose();
    _cachedVideo?.style.display = 'block';
    try {
      _cachedVideo?.pause();
      _cachedVideo?.srcObject = null;
    } catch (_) {}
    try {
      _jsStop();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isRecording && _pendingResult == null && _pickedGalleryItems.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _isRecording) return;
        if (_pendingResult != null) {
          _retake();
        } else if (_pickedGalleryItems.isNotEmpty) {
          setState(() => _pickedGalleryItems = []);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: const HtmlElementView(viewType: _viewType),
            ),
            if (!_isInitialized)
              Container(
                color: Colors.black,
                child: Center(
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54),
                          ),
                        )
                      : CircularProgressIndicator(color: context.accentColor),
                ),
              ),

            // Top bar — close on the left, vertically centered zoom pill, flash on the right
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      RoundIconButton(
                        icon: Icons.close,
                        onTap: _isRecording ? null : () => Navigator.of(context).pop(),
                      ),
                      if (_zoomSupported && _isInitialized)
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _isPinching ? 1.0 : 0.0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              '${_currentZoom.toStringAsFixed(1)}x',
                              style: AppTypography.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 46),
                      RoundIconButton(
                        icon: _torchEnabled ? Icons.flash_on : Icons.flash_off,
                        iconColor: _torchEnabled ? context.accentColor : null,
                        onTap: _isRecording ? null : _toggleTorch,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Mode toggle + shutter + camera flip
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_isRecording) ...[
                        ModeToggle(
                          isVideoMode: _isVideoMode,
                          onChanged: _setMode,
                          accentColor: context.accentColor,
                        ),
                        const SizedBox(height: 20),
                      ] else
                        const SizedBox(height: 20 + 34 + 20),
                      SizedBox(
                        width: double.infinity,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            ShutterButton(
                              isVideoMode: _isVideoMode,
                              isRecording: _isRecording,
                              recordProgress: _isRecording
                                  ? (_recordSeconds / (maxRecordSeconds * 10)).clamp(0.0, 1.0)
                                  : null,
                              isBusy: _isBusy,
                              onTap: _onShutterTap,
                              onLongPress: _onShutterLongPress,
                            ),
                            Positioned(
                              left: 24,
                              child: GalleryShortcutButton(
                                onTap: _isRecording ? null : _openGallery,
                              ),
                            ),
                            Positioned(
                              right: 24,
                              child: RoundIconButton(
                                icon: Icons.flip_camera_ios_outlined,
                                onTap: _isRecording ? null : _switchCamera,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (_pendingResult != null)
              CaptureReview(
                result: _pendingResult!,
                videoController: _reviewVideoController,
                onRetake: _retake,
                onUse: _useCapture,
              ),

            if (_pickedGalleryItems.isNotEmpty)
              GalleryReview(
                items: _pickedGalleryItems,
                onRemove: _removePickedGalleryItem,
                onCancel: () => setState(() => _pickedGalleryItems = []),
                onUse: _usePickedGalleryItems,
              ),
          ],
        ),
      ),
    );
  }
}


