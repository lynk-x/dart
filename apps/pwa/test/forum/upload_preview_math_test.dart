import 'package:flutter_test/flutter_test.dart';
import 'package:lynk_x/presentation/features/forum/core/upload_preview_math.dart';

const mb = 1024 * 1024;
UploadItemInfo photo(String name, double sizeMb) => UploadItemInfo(name: name, bytes: (sizeMb * mb).round());

void main() {
  group('file types', () {
    test('videos are recognised by extension, case-insensitively', () {
      expect(const UploadItemInfo(name: 'clip.MP4', bytes: 1).isVideo, isTrue);
      expect(const UploadItemInfo(name: 'a.mov', bytes: 1).isVideo, isTrue);
      expect(const UploadItemInfo(name: 'a.jpg', bytes: 1).isVideo, isFalse);
      expect(const UploadItemInfo(name: 'no_extension', bytes: 1).isVideo, isFalse);
    });

    test('gif and svg are kept as they are, other photos are resizable', () {
      expect(const UploadItemInfo(name: 'a.gif', bytes: 1).isResizablePhoto, isFalse);
      expect(const UploadItemInfo(name: 'a.svg', bytes: 1).isResizablePhoto, isFalse);
      expect(const UploadItemInfo(name: 'a.heic', bytes: 1).isResizablePhoto, isTrue);
      expect(const UploadItemInfo(name: 'a.mp4', bytes: 1).isResizablePhoto, isFalse);
    });
  });

  group('estimateOptimizedBytes', () {
    test('a big photo shrinks to about the typical optimized size', () {
      expect(estimateOptimizedBytes(photo('a.jpg', 4.2)), kOptimizedPhotoEstimateBytes);
    });

    test('a small photo is never estimated larger than itself', () {
      final small = const UploadItemInfo(name: 'a.jpg', bytes: 120 * 1024);
      expect(estimateOptimizedBytes(small), 120 * 1024);
    });

    test('videos and keep-as-is formats are unchanged', () {
      expect(estimateOptimizedBytes(photo('clip.mp4', 38)), (38 * mb));
      expect(estimateOptimizedBytes(photo('anim.gif', 6)), (6 * mb));
    });
  });

  group('summarizeUpload', () {
    final items = [photo('1.jpg', 4.2), photo('2.jpg', 3.8), photo('3.jpg', 5.1)];

    test('original total is the sum of the files, exactly', () {
      final s = summarizeUpload(items, original: true);
      expect(s.totalBytes, s.originalTotalBytes);
      expect(formatMegabytes(s.totalBytes), '13.1 MB');
      expect(s.photoCount, 3);
      expect(s.videoCount, 0);
    });

    test('optimized total is far smaller', () {
      final s = summarizeUpload(items, original: false);
      expect(s.totalBytes, 3 * kOptimizedPhotoEstimateBytes);
      expect(s.totalBytes, lessThan(s.originalTotalBytes ~/ 4));
    });

    test('the data warning shows only for a large ORIGINAL upload with photos', () {
      expect(summarizeUpload(items, original: true).showsDataWarning, isTrue);
      expect(summarizeUpload(items, original: false).showsDataWarning, isFalse);
      expect(summarizeUpload([photo('1.jpg', 2)], original: true).showsDataWarning, isFalse);
    });

    test('a video counts toward the total unchanged and is counted separately', () {
      final withVideo = [...items, photo('clip.mp4', 38)];
      final original = summarizeUpload(withVideo, original: true);
      final optimized = summarizeUpload(withVideo, original: false);
      expect(original.videoCount, 1);
      expect(optimized.totalBytes, 3 * kOptimizedPhotoEstimateBytes + 38 * mb);
      expect(original.totalBytes - optimized.totalBytes, original.originalTotalBytes - optimized.optimizedTotalBytes);
    });

    test('a video-only selection never shows the photo data warning', () {
      expect(summarizeUpload([photo('clip.mp4', 90)], original: true).showsDataWarning, isFalse);
    });
  });

  group('wording', () {
    test('formatMegabytes', () {
      expect(formatMegabytes(0), '0 MB');
      expect(formatMegabytes(10), '<0.1 MB');
      expect(formatMegabytes((13.14 * mb).round()), '13.1 MB');
      expect(formatMegabytes(mb), '1.0 MB');
    });

    test('describeSelection pluralises and joins without a list comma', () {
      expect(describeSelection(1, 0), '1 photo');
      expect(describeSelection(3, 0), '3 photos');
      expect(describeSelection(0, 2), '2 videos');
      expect(describeSelection(3, 1), '3 photos and 1 video');
      expect(describeSelection(1, 1), '1 photo and 1 video');
    });
  });
}
