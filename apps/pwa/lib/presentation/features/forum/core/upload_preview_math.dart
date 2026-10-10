// Pure logic behind the upload preview sheet: what counts as a photo or video, how big the upload
// will be, and how to word it. Kept free of Flutter and web imports so it is unit-testable and so
// ForumMediaCubit and the sheet agree on the same file-type rules.

/// Extensions treated as video. Videos are uploaded as they are (no re-encoding).
const kUploadVideoExtensions = {'mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi', '3gp'};

/// Photo formats that are never re-encoded to JPEG: re-encoding would destroy an animation (GIF)
/// or turn a vector into pixels (SVG). They upload at their original size either way.
const kUploadKeepAsIsExtensions = {'gif', 'svg'};

/// What a downscaled photo typically weighs. The upload resizes the long edge to 2048 px at JPEG
/// quality 85, which lands between about 0.4 and 0.9 MB depending on the scene, almost regardless of
/// how large the original was. The sheet shows this as an estimate ("about"), not a promise.
const kOptimizedPhotoEstimateBytes = 700 * 1024;

/// Total upload above which choosing original quality shows a mobile-data warning.
const kDataWarningBytes = 10 * 1024 * 1024;

/// One picked file, reduced to what the size maths needs.
class UploadItemInfo {
  final String name;
  final int bytes;

  const UploadItemInfo({required this.name, required this.bytes});

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  bool get isVideo => kUploadVideoExtensions.contains(extension);

  /// True for photos that the optimized path will actually shrink.
  bool get isResizablePhoto => !isVideo && !kUploadKeepAsIsExtensions.contains(extension);
}

/// Estimated size of [item] when sent optimized. Never larger than the original (a small photo is
/// uploaded as it is), and videos and keep-as-is formats are unchanged.
int estimateOptimizedBytes(UploadItemInfo item) {
  if (!item.isResizablePhoto) return item.bytes;
  return item.bytes < kOptimizedPhotoEstimateBytes ? item.bytes : kOptimizedPhotoEstimateBytes;
}

/// Totals for the sheet at the current quality choice.
class UploadSummary {
  final int photoCount;
  final int videoCount;
  final int totalBytes;
  final int originalTotalBytes;
  final int optimizedTotalBytes;

  /// True when sending originals would use a lot of mobile data.
  final bool showsDataWarning;

  const UploadSummary({
    required this.photoCount,
    required this.videoCount,
    required this.totalBytes,
    required this.originalTotalBytes,
    required this.optimizedTotalBytes,
    required this.showsDataWarning,
  });
}

UploadSummary summarizeUpload(List<UploadItemInfo> items, {required bool original}) {
  var photos = 0, videos = 0, originalTotal = 0, optimizedTotal = 0;
  for (final item in items) {
    item.isVideo ? videos++ : photos++;
    originalTotal += item.bytes;
    optimizedTotal += estimateOptimizedBytes(item);
  }
  final total = original ? originalTotal : optimizedTotal;
  return UploadSummary(
    photoCount: photos,
    videoCount: videos,
    totalBytes: total,
    originalTotalBytes: originalTotal,
    optimizedTotalBytes: optimizedTotal,
    showsDataWarning: original && photos > 0 && total > kDataWarningBytes,
  );
}

/// "13.1 MB". One decimal, never "0.0 MB" for a non-empty file.
String formatMegabytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  final mb = bytes / (1024 * 1024);
  if (mb < 0.1) return '<0.1 MB';
  return '${mb.toStringAsFixed(1)} MB';
}

/// "3 photos", "1 photo", "2 videos", "3 photos and 1 video".
String describeSelection(int photos, int videos) {
  final parts = <String>[
    if (photos > 0) '$photos ${photos == 1 ? 'photo' : 'photos'}',
    if (videos > 0) '$videos ${videos == 1 ? 'video' : 'videos'}',
  ];
  return parts.join(' and ');
}
