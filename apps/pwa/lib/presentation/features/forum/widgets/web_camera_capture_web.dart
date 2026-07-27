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
  /// Non-empty when the user picked existing files via the in-screen
  /// gallery shortcut instead of capturing — objectUrl/isVideo are unused
  /// placeholders in that case. media_tab.dart checks this and uploads
  /// these directly through the same path as a normal gallery pick.
  final List<XFile> pickedFiles;

  const WebCameraCaptureResult({required this.objectUrl, required this.isVideo})
      : pickedFiles = const [];

  const WebCameraCaptureResult.pickedFiles(this.pickedFiles)
      : objectUrl = '',
        isVideo = false;
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

  // Purely a preview-layer CSS transform on the <video> element — matches
  // the "mirror" convention every native camera app uses for the front
  // camera (shows what you'd see in a mirror). capturePhoto()/MediaRecorder
  // both read from the underlying video/stream source directly, not the
  // DOM element's rendered/transformed output, so captured photos and
  // recordings are never mirrored regardless of this.
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

  Future<void> _onShutterTap() async {
    if (_isBusy || !_isInitialized) return;

    if (!_isVideoMode) {
      setState(() => _isBusy = true);
      try {
        final result = await _jsCapturePhoto().toDart;
        final url = result?.toDart;
        if (!mounted) return;
        if (url == null || url.isEmpty) {
          setState(() {
            _isBusy = false;
            _error = 'Failed to capture photo.';
          });
          return;
        }
        setState(() {
          _isBusy = false;
          _pendingResult = WebCameraCaptureResult(objectUrl: url, isVideo: false);
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isBusy = false;
          _error = 'Failed to capture photo: $e';
        });
      }
      return;
    }

    if (!_isRecording) {
      final started = _jsStartRecording().toDart;
      if (!started) {
        setState(() => _error = 'Failed to start recording.');
        return;
      }
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordSeconds++);
      });
    } else {
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
  }

  String get _recordTimeLabel {
    final m = (_recordSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_recordSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
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
      controller.play();
      setState(() {
        _isBusy = false;
        _reviewVideoController = controller;
        _pendingResult = WebCameraCaptureResult(objectUrl: url, isVideo: true);
      });
    } catch (e) {
      controller.dispose();
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _error = 'Failed to load recording: $e';
      });
    }
  }

  // Discards the pending capture and returns to the live camera preview.
  // The stream itself is never stopped/restarted here — only started once
  // in initState and stopped once in dispose — so retaking is instant.
  void _retake() {
    _jsRevokeObjectUrl(_pendingResult!.objectUrl.toJS);
    _reviewVideoController?.dispose();
    setState(() {
      _pendingResult = null;
      _reviewVideoController = null;
    });
  }

  void _useCapture() {
    Navigator.of(context).pop(_pendingResult);
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _reviewVideoController?.dispose();
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
            if (_zoomSupported && _isInitialized)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 56),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                    ),
                  ),
                ),
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

            // Top bar — close on the left, flash on the right (dimmed while
            // recording, since switching camera/torch mid-recording isn't
            // supported by the underlying MediaRecorder stream). Explicitly
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _RoundIconButton(
                        icon: Icons.close,
                        onTap: _isRecording ? null : () => Navigator.of(context).pop(),
                      ),
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

            // Recording indicator — centered independently of the top bar's
            // two end-aligned icons, rather than competing for a slot in
            // that row.
            if (_isRecording)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _PulsingDot(),
                            const SizedBox(width: 6),
                            Text(
                              _recordTimeLabel,
                              style: AppTypography.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                              isBusy: _isBusy,
                              onTap: _onShutterTap,
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
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: SizedBox(
                height: 50,
                width: double.infinity,
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
class _CaptureReview extends StatelessWidget {
  final WebCameraCaptureResult result;
  final VideoPlayerController? videoController;
  final VoidCallback onRetake;
  final VoidCallback onUse;

  const _CaptureReview({
    required this.result,
    required this.videoController,
    required this.onRetake,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: result.isVideo
                ? (videoController != null && videoController!.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: videoController!.value.aspectRatio,
                        child: VideoPlayer(videoController!),
                      )
                    : CircularProgressIndicator(color: context.accentColor))
                : Image.network(result.objectUrl, fit: BoxFit.contain),
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
                          onPressed: onRetake,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: PrimaryButton(
                        icon: Icons.check_circle_outline,
                        text: result.isVideo ? 'Use Video' : 'Use Photo',
                        backgroundColor: context.accentColor,
                        textColor: Colors.black,
                        onPressed: onUse,
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
  final bool isBusy;
  final VoidCallback onTap;

  const _ShutterButton({
    required this.isVideoMode,
    required this.isRecording,
    required this.isBusy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isBusy ? null : onTap,
      child: Container(
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

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.3).animate(_controller),
      child: const _Dot(),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
    );
  }
}
