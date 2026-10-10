import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/core/upload_preview_math.dart';

/// What the user decided in the upload preview. A cancelled sheet returns null instead.
class UploadChoice {
  /// Send photos untouched instead of downscaling them.
  final bool keepOriginal;
  const UploadChoice({required this.keepOriginal});
}

/// Produces a still frame for a video tile (null if the browser can't decode it).
typedef VideoThumbnailLoader = Future<Uint8List?> Function(XFile file);

/// Shows the preview after photos or videos are picked or captured, before anything uploads.
///
/// Lists what is about to be sent with the upload size, and lets people who may send originals
/// (organizers, moderators, premium members) switch it on. Everyone else sees that photos are
/// optimized, with no choice offered. Returns null if the user cancels.
Future<UploadChoice?> showUploadPreviewSheet(
  BuildContext context, {
  required List<XFile> files,
  required String forumName,
  required bool canChooseOriginal,
  VideoThumbnailLoader? loadVideoThumbnail,
}) {
  return showModalBottomSheet<UploadChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => UploadPreviewSheet(
      files: files,
      forumName: forumName,
      canChooseOriginal: canChooseOriginal,
      loadVideoThumbnail: loadVideoThumbnail,
    ),
  );
}

class UploadPreviewSheet extends StatefulWidget {
  final List<XFile> files;
  final String forumName;
  final bool canChooseOriginal;
  final VideoThumbnailLoader? loadVideoThumbnail;

  const UploadPreviewSheet({
    super.key,
    required this.files,
    required this.forumName,
    required this.canChooseOriginal,
    this.loadVideoThumbnail,
  });

  @override
  State<UploadPreviewSheet> createState() => _UploadPreviewSheetState();
}

class _UploadPreviewSheetState extends State<UploadPreviewSheet> {
  static const _sheetColor = Color(0xFF17171A);
  static const _tileSize = 66.0;

  List<UploadItemInfo>? _items;
  final Map<int, Uint8List> _thumbs = {};

  // People who may send originals start on it, as designed; everyone else has no choice.
  late bool _original = widget.canChooseOriginal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Sizes first (cheap), so the totals appear straight away; thumbnails fill in after.
    final items = <UploadItemInfo>[];
    for (final file in widget.files) {
      items.add(UploadItemInfo(name: file.name, bytes: await file.length()));
    }
    if (!mounted) return;
    setState(() => _items = items);

    for (var i = 0; i < widget.files.length; i++) {
      Uint8List? bytes;
      try {
        bytes = items[i].isVideo
            ? await widget.loadVideoThumbnail?.call(widget.files[i])
            : await widget.files[i].readAsBytes();
      } catch (_) {
        bytes = null; // a tile without a preview is fine; the file still uploads
      }
      if (!mounted) return;
      if (bytes != null) setState(() => _thumbs[i] = bytes!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    final items = _items;
    final summary = items == null ? null : summarizeUpload(items, original: _original && widget.canChooseOriginal);
    final selection = summary == null ? null : describeSelection(summary.photoCount, summary.videoCount);

    return Container(
      decoration: const BoxDecoration(
        color: _sheetColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Ready to send', style: AppTypography.interTight(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 2),
            Text(
              selection == null ? 'Preparing…' : '$selection for ${widget.forumName}',
              style: AppTypography.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.66)),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: _tileSize,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.files.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _tile(i, items == null ? false : items[i].isVideo),
              ),
            ),
            const SizedBox(height: 14),
            if (summary != null) _qualityArea(accent, summary),
            const SizedBox(height: 14),
            if (summary != null) ...[
              _sizeRow(summary),
              if (summary.showsDataWarning) _dataWarning(summary),
              const SizedBox(height: 14),
            ],
            ElevatedButton(
              key: const Key('upload-preview-send'),
              onPressed: items == null
                  ? null
                  : () => Navigator.of(context).pop(UploadChoice(keepOriginal: _original && widget.canChooseOriginal)),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                selection == null ? 'Send' : 'Send $selection',
                style: AppTypography.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black),
              ),
            ),
            TextButton(
              key: const Key('upload-preview-cancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: AppTypography.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.66))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(int index, bool isVideo) {
    final thumb = _thumbs[index];
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: _tileSize,
        height: _tileSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumb != null)
              Image.memory(
                thumb,
                fit: BoxFit.cover,
                cacheWidth: (_tileSize * 2).toInt(),
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _placeholder(isVideo),
              )
            else
              _placeholder(isVideo),
            if (isVideo)
              Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(bool isVideo) => Container(
        color: AppColors.surface,
        child: Icon(isVideo ? Icons.videocam_rounded : Icons.image_rounded, color: Colors.white24, size: 24),
      );

  Widget _qualityArea(Color accent, UploadSummary summary) {
    if (summary.photoCount == 0) {
      return _infoLine(summary.videoCount == 1 ? 'The video is sent as it is.' : 'Videos are sent as they are.');
    }
    if (!widget.canChooseOriginal) {
      final videoNote = summary.videoCount == 0
          ? ''
          : (summary.videoCount == 1 ? ' The video is sent as it is.' : ' Videos are sent as they are.');
      return _infoLine('Photos are optimized for faster upload.$videoNote');
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Send original quality', style: AppTypography.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(
                    _original ? 'Full resolution. Larger upload.' : 'Optimized for a faster upload.',
                    style: AppTypography.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.66)),
                  ),
                ],
              ),
            ),
            Switch(
              key: const Key('upload-preview-original-switch'),
              value: _original,
              onChanged: (value) => setState(() => _original = value),
              thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.black : Colors.white),
              trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : const Color(0xFF48484C)),
              trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoLine(String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: Colors.white.withValues(alpha: 0.66)),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: AppTypography.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.66)))),
          ],
        ),
      );

  Widget _sizeRow(UploadSummary summary) {
    // Sending originals reports the exact size. Optimized is an estimate until the photos are processed.
    final isEstimate = !(_original && widget.canChooseOriginal) && (_items?.any((i) => i.isResizablePhoto) ?? false);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('Upload size', style: AppTypography.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.66))),
        Text(
          '${isEstimate ? 'About ' : ''}${formatMegabytes(summary.totalBytes)}',
          key: const Key('upload-preview-size'),
          style: AppTypography.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ],
    );
  }

  Widget _dataWarning(UploadSummary summary) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 15, color: Color(0xFFF9C920)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Uses about ${formatMegabytes(summary.totalBytes)} of mobile data',
                style: AppTypography.inter(fontSize: 12, color: const Color(0xFFF9C920)),
              ),
            ),
          ],
        ),
      );
}
