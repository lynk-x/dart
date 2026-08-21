import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import 'package:lynk_x/presentation/shared/utils/permission_acks.dart';

@JS('window.flutterCameraStream.start')
external JSPromise<JSBoolean> _jsStart(JSString videoElementId, JSString facingMode);

@JS('window.flutterCameraStream.stop')
external void _jsStop();

@JS('window.flutterCameraStream.switchCamera')
external JSPromise<JSBoolean> _jsSwitchCamera();

@JS('window.flutterCameraStream.capturePhoto')
external JSPromise<JSString?> _jsCapturePhoto();

@JS('window.flutterCameraStream.startRecording')
external JSBoolean _jsStartRecording();

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

class WebCameraCaptureResult {
  final String objectUrl;
  final bool isVideo;
  final bool isMuted;
  /// Non-empty when the user picked existing files via the in-screen
  /// gallery shortcut instead of capturing — objectUrl/isVideo are unused
  /// placeholders in that case. media_tab.dart checks this and uploads
  /// these directly through the same path as a normal gallery pick.
  final List<XFile> pickedFiles;

  const WebCameraCaptureResult({
    required this.objectUrl,
    required this.isVideo,
    this.isMuted = false,
  }) : pickedFiles = const [];

  const WebCameraCaptureResult.pickedFiles(this.pickedFiles)
      : objectUrl = '',
        isVideo = false,
        isMuted = false;
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
  List<_PickedMediaItem> _pickedGalleryItems = [];

  // Null when the active camera doesn't report a zoom capability (common on
  // desktop webcams, Firefox, and some Android builds) — the pinch gesture
  // simply does nothing in that case rather than showing a dead control.
  double? _zoomMin;
  double? _zoomMax;
  double _currentZoom = 1.0;
  double _pinchStartZoom = 1.0;

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

  void _onScaleStart(ScaleStartDetails details) {
    _pinchStartZoom = _currentZoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_zoomSupported || _isBusy) return;
    final min = _zoomMin!;
    final max = _zoomMax!;
    final next = (_pinchStartZoom * details.scale).clamp(min, max);
    if ((next - _currentZoom).abs() < 0.01) return;
    _currentZoom = next;
    // Fire-and-forget: constraint updates are cheap and frequent during a
    // pinch gesture, no need to await/serialize them against setState.
    _jsSetZoom(next.toJS);
    if (mounted) setState(() {});
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
        ..style.objectFit = 'contain';

      _cachedVideo!.setAttribute('playsinline', 'true');
      _cachedVideo!.setAttribute('autoplay', 'true');
      _cachedVideo!.setAttribute('muted', 'true');
    } else {
      _cachedVideo!.style.objectFit = 'contain';
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

      final items = <_PickedMediaItem>[];
      for (final file in files) {
        final bytes = await file.readAsBytes();
        items.add(_PickedMediaItem(file: file, bytes: bytes));
      }
      if (items.isEmpty || !mounted) return;

      setState(() => _pickedGalleryItems = items);
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.showError(context, 'Could not access your media library.');
    }
  }

  void _removePickedGalleryItem(_PickedMediaItem item) {
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

    final started = _jsStartRecording().toDart;
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
    _recordTimer?.cancel();
    if (_pendingResult != null && _pendingResult!.objectUrl.isNotEmpty) {
      try {
        _jsRevokeObjectUrl(_pendingResult!.objectUrl.toJS);
      } catch (_) {}
    }
    _reviewVideoController?.dispose();
    _cachedVideo?.style.display = 'block';
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
                      _RoundIconButton(
                        icon: Icons.close,
                        onTap: _isRecording ? null : () => Navigator.of(context).pop(),
                      ),
                      if (_zoomSupported && _isInitialized)
                        Container(
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
                        )
                      else
                        const SizedBox(width: 46),
                      _RoundIconButton(
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
                        _ModeToggle(
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
                            _ShutterButton(
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
                              child: _GalleryShortcutButton(
                                onTap: _isRecording ? null : _openGallery,
                              ),
                            ),
                            Positioned(
                              right: 24,
                              child: _RoundIconButton(
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
              _CaptureReview(
                result: _pendingResult!,
                videoController: _reviewVideoController,
                onRetake: _retake,
                onUse: _useCapture,
              ),

            if (_pickedGalleryItems.isNotEmpty)
              _GalleryReview(
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

const _videoExtensions = {
  'mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi', '3gp',
};

/// One file picked via the gallery shortcut, pending review. Identity
/// (`==`) is the default object identity — fine here since each pick
/// produces distinct PlatformFile instances even for same-named files.
class _PickedMediaItem {
  final XFile file;
  final Uint8List bytes;

  _PickedMediaItem({required this.file, required this.bytes});

  bool get isVideo {
    final ext = file.name.split('.').last.toLowerCase();
    return _videoExtensions.contains(ext);
  }
}

/// Grid review shown after a gallery pick, before the files are handed
/// back to the caller — mirrors [_CaptureReview]'s "don't upload until
/// confirmed" principle, but as a grid (with per-item removal) rather than
/// single-item Retake/Use, since FileType.media allows multi-select and
/// mixed image/video types in one pick.
class _GalleryReview extends StatelessWidget {
  final List<_PickedMediaItem> items;
  final ValueChanged<_PickedMediaItem> onRemove;
  final VoidCallback onCancel;
  final VoidCallback onUse;

  const _GalleryReview({
    required this.items,
    required this.onRemove,
    required this.onCancel,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${items.length} selected',
                    style: AppTypography.interTight(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  _RoundIconButton(icon: Icons.close, onTap: onCancel),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'No items left — cancel to go back to the camera.',
                        textAlign: TextAlign.center,
                        style: AppTypography.inter(fontSize: 13, color: Colors.white54),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _GalleryReviewTile(
                          item: item,
                          onRemove: () => onRemove(item),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: PrimaryButton(
                icon: Icons.check_circle_outline,
                text: items.isEmpty
                    ? 'Use Selected'
                    : 'Use ${items.length} ${items.length == 1 ? 'item' : 'items'}',
                backgroundColor: context.accentColor,
                textColor: Colors.black,
                onPressed: items.isEmpty ? null : onUse,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryReviewTile extends StatelessWidget {
  final _PickedMediaItem item;
  final VoidCallback onRemove;

  const _GalleryReviewTile({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.isVideo)
            Container(
              color: Colors.grey[900],
              child: const Center(
                child: Icon(Icons.play_circle_fill, color: Colors.white38, size: 32),
              ),
            )
          else
            Image.memory(item.bytes, fit: BoxFit.cover),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen review shown after capture, before the result is handed back
/// to the caller — lets a bad take (blocked framing, motion blur, wrong
/// mode) be discarded and retaken instead of only being catchable after
/// upload via delete/report.
class _CaptureReview extends StatefulWidget {
  final WebCameraCaptureResult result;
  final VideoPlayerController? videoController;
  final VoidCallback onRetake;
  final Function(bool isMuted) onUse;

  const _CaptureReview({
    required this.result,
    required this.videoController,
    required this.onRetake,
    required this.onUse,
  });

  @override
  State<_CaptureReview> createState() => _CaptureReviewState();
}

class _CaptureReviewState extends State<_CaptureReview> {
  late bool _isMuted;

  @override
  void initState() {
    super.initState();
    _isMuted = widget.videoController?.value.volume == 0.0;
  }

  void _toggleMute() {
    if (widget.videoController == null) return;
    setState(() {
      _isMuted = !_isMuted;
      widget.videoController!.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: widget.result.isVideo
                ? (widget.videoController != null && widget.videoController!.value.isInitialized
                    ? GestureDetector(
                        onTap: () {
                          if (widget.videoController!.value.isPlaying) {
                            widget.videoController!.pause();
                          } else {
                            widget.videoController!.play();
                          }
                        },
                        child: SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: widget.videoController!.value.size.width > 0
                                  ? widget.videoController!.value.size.width
                                  : 1280,
                              height: widget.videoController!.value.size.height > 0
                                  ? widget.videoController!.value.size.height
                                  : 720,
                              child: VideoPlayer(widget.videoController!),
                            ),
                          ),
                        ),
                      )
                    : CircularProgressIndicator(color: context.accentColor))
                : SizedBox.expand(
                    child: Image.network(widget.result.objectUrl, fit: BoxFit.cover),
                  ),
          ),
          if (widget.result.isVideo && widget.videoController != null)
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: GestureDetector(
                  onTap: _toggleMute,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          color: _isMuted ? Colors.redAccent : context.accentColor,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isMuted ? 'Muted' : 'Audio On',
                          style: AppTypography.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.replay, size: 20),
                          label: Text(
                            'Retake',
                            style: AppTypography.interTight(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: widget.onRetake,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: PrimaryButton(
                        icon: Icons.check_circle_outline,
                        text: widget.result.isVideo ? 'Use Video' : 'Use Photo',
                        backgroundColor: context.accentColor,
                        textColor: Colors.black,
                        onPressed: () => widget.onUse(_isMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool isVideoMode;
  final ValueChanged<bool> onChanged;
  final Color accentColor;

  const _ModeToggle({
    required this.isVideoMode,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeOption(
            label: 'Photo',
            active: !isVideoMode,
            activeColor: accentColor,
            activeTextColor: Colors.black,
            onTap: () => onChanged(false),
          ),
          _ModeOption(
            label: 'Video',
            active: isVideoMode,
            activeColor: Colors.redAccent,
            activeTextColor: Colors.white,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final Color activeTextColor;
  final VoidCallback onTap;

  const _ModeOption({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.activeTextColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: AppTypography.inter(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: active ? activeTextColor : Colors.white54,
          ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final bool isVideoMode;
  final bool isRecording;
  final double? recordProgress;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ShutterButton({
    required this.isVideoMode,
    required this.isRecording,
    this.recordProgress,
    required this.isBusy,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isBusy ? null : onTap,
      onLongPress: isBusy ? null : onLongPress,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isRecording && recordProgress != null)
            SizedBox(
              width: 76,
              height: 76,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: recordProgress!),
                duration: const Duration(milliseconds: 100),
                curve: Curves.linear,
                builder: (context, animatedProgress, child) {
                  return CircularProgressIndicator(
                    value: animatedProgress,
                    strokeWidth: 3.5,
                    color: Colors.redAccent,
                    backgroundColor: Colors.white24,
                  );
                },
              ),
            ),
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3.5),
            ),
            child: Center(
              child: isBusy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: isVideoMode && isRecording ? 26 : 54,
                      height: isVideoMode && isRecording ? 26 : 54,
                      decoration: BoxDecoration(
                        color: isVideoMode ? Colors.redAccent : Colors.white,
                        borderRadius: BorderRadius.circular(
                          isVideoMode && isRecording ? 6 : 27,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}


class _GalleryShortcutButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _GalleryShortcutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Icon(
          Icons.photo_library_outlined,
          color: onTap == null ? Colors.white24 : Colors.white70,
          size: 26,
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? iconColor;

  const _RoundIconButton({required this.icon, required this.onTap, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.4),
        ),
        child: Icon(
          icon,
          color: onTap == null ? Colors.white24 : (iconColor ?? Colors.white),
          size: 24,
        ),
      ),
    );
  }
}
