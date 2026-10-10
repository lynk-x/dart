import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lynk_x/presentation/features/forum/widgets/upload_preview_sheet.dart';

const mb = 1024 * 1024;

// A real 1x1 PNG so the thumbnail tiles decode.
final Uint8List _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

/// A fake picked file: tiny real bytes, but reporting [sizeMb] as its length.
XFile _file(String name, double sizeMb) =>
    XFile.fromData(_png, path: '/tmp/$name', name: name, length: (sizeMb * mb).round(), mimeType: name.endsWith('.mp4') ? 'video/mp4' : 'image/jpeg');

List<XFile> get _threePhotos => [_file('1.jpg', 4.2), _file('2.jpg', 3.8), _file('3.jpg', 5.1)];

/// Opens the sheet from a button and exposes what it returned.
class _Harness {
  final Completer<UploadChoice?> result = Completer();
  bool done = false;

  Widget app({required List<XFile> files, required bool canChooseOriginal}) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await showUploadPreviewSheet(
                    context,
                    files: files,
                    forumName: 'Nairobi Jazz Night',
                    canChooseOriginal: canChooseOriginal,
                    loadVideoThumbnail: (_) async => _png,
                  );
                  done = true;
                  result.complete(r);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
}

Future<_Harness> _open(WidgetTester tester, {required List<XFile> files, required bool canChooseOriginal}) async {
  final h = _Harness();
  await tester.pumpWidget(h.app(files: files, canChooseOriginal: canChooseOriginal));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return h;
}

String _size(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('upload-preview-size'))).data!;

void main() {
  testWidgets('organizer: starts on original with exact size, data warning and a switch', (tester) async {
    await _open(tester, files: _threePhotos, canChooseOriginal: true);

    expect(find.text('Ready to send'), findsOneWidget);
    expect(find.text('3 photos for Nairobi Jazz Night'), findsOneWidget);
    expect(tester.widget<Switch>(find.byKey(const Key('upload-preview-original-switch'))).value, isTrue);
    expect(_size(tester), '13.1 MB');
    expect(find.text('Uses about 13.1 MB of mobile data'), findsOneWidget);
    expect(find.text('Send 3 photos'), findsOneWidget);
  });

  testWidgets('switching original off shows the optimized estimate and drops the warning', (tester) async {
    await _open(tester, files: _threePhotos, canChooseOriginal: true);
    await tester.tap(find.byKey(const Key('upload-preview-original-switch')));
    await tester.pumpAndSettle();

    expect(_size(tester), 'About 2.1 MB');
    expect(find.textContaining('mobile data'), findsNothing);
    expect(find.text('Optimized for a faster upload.'), findsOneWidget);
  });

  testWidgets('sending returns the choice: original by default, optimized after switching off', (tester) async {
    final h = await _open(tester, files: _threePhotos, canChooseOriginal: true);
    await tester.tap(find.byKey(const Key('upload-preview-send')));
    await tester.pumpAndSettle();
    expect((await h.result.future)!.keepOriginal, isTrue);

    final h2 = await _open(tester, files: _threePhotos, canChooseOriginal: true);
    await tester.tap(find.byKey(const Key('upload-preview-original-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload-preview-send')));
    await tester.pumpAndSettle();
    expect((await h2.result.future)!.keepOriginal, isFalse);
  });

  testWidgets('cancel returns null so nothing uploads', (tester) async {
    final h = await _open(tester, files: _threePhotos, canChooseOriginal: true);
    await tester.tap(find.byKey(const Key('upload-preview-cancel')));
    await tester.pumpAndSettle();
    expect(await h.result.future, isNull);
  });

  testWidgets('attendee: no switch, an explanation, an estimate, and never original', (tester) async {
    final h = await _open(tester, files: _threePhotos, canChooseOriginal: false);

    expect(find.byKey(const Key('upload-preview-original-switch')), findsNothing);
    expect(find.text('Photos are optimized for faster upload.'), findsOneWidget);
    expect(_size(tester), 'About 2.1 MB');
    await tester.tap(find.byKey(const Key('upload-preview-send')));
    await tester.pumpAndSettle();
    expect((await h.result.future)!.keepOriginal, isFalse);
  });

  testWidgets('photos and a video: video counted, noted for attendees, and sent unchanged in the total', (tester) async {
    await _open(tester, files: [..._threePhotos, _file('clip.mp4', 38)], canChooseOriginal: false);
    expect(find.text('3 photos and 1 video for Nairobi Jazz Night'), findsOneWidget);
    expect(find.text('Photos are optimized for faster upload. The video is sent as it is.'), findsOneWidget);
    expect(_size(tester), 'About 40.1 MB');
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('video only: no quality choice at all, exact size, no estimate wording', (tester) async {
    final h = await _open(tester, files: [_file('clip.mp4', 38)], canChooseOriginal: true);
    expect(find.byKey(const Key('upload-preview-original-switch')), findsNothing);
    expect(find.text('The video is sent as it is.'), findsOneWidget);
    expect(_size(tester), '38.0 MB');
    expect(find.text('Send 1 video'), findsOneWidget);
    await tester.tap(find.byKey(const Key('upload-preview-send')));
    await tester.pumpAndSettle();
    // A video-only batch has no photos to keep original, but the organizer default still travels.
    expect((await h.result.future)!.keepOriginal, isTrue);
  });

  testWidgets('a single small photo is not warned about and reads as one photo', (tester) async {
    await _open(tester, files: [_file('a.jpg', 1.5)], canChooseOriginal: true);
    expect(find.text('1 photo for Nairobi Jazz Night'), findsOneWidget);
    expect(_size(tester), '1.5 MB');
    expect(find.textContaining('mobile data'), findsNothing);
    expect(find.text('Send 1 photo'), findsOneWidget);
  });

  testWidgets('the switch is announced to screen readers with its label', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester, files: _threePhotos, canChooseOriginal: true);
    expect(find.bySemanticsLabel(RegExp('Send original quality')), findsWidgets);
    handle.dispose();
  });
}
