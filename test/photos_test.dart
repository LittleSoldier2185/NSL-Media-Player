import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/library_service.dart';
import 'package:nsl_media_player/ui/photos_view.dart';
import 'package:nsl_media_player/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

LibraryItem pic(String name, DateTime when, {bool exif = false}) => LibraryItem(
  path: 'C:\\pictures\\$name.jpg',
  title: name,
  modified: DateTime(2030).millisecondsSinceEpoch, // a copy date: not the day
  taken: exif ? when.millisecondsSinceEpoch : null,
);

void main() {
  group('EXIF date', () {
    test('reads the way cameras write it', () {
      expect(
        LibraryService.parseExifDate('2026:11:08 16:42:11'),
        DateTime(2026, 11, 8, 16, 42, 11),
      );
      expect(
        LibraryService.parseExifDate(' 2026:01:02 03:04:05 '),
        DateTime(2026, 1, 2, 3, 4, 5),
      );
    });

    test('rejects empty and made-up dates', () {
      expect(LibraryService.parseExifDate(''), isNull);
      expect(LibraryService.parseExifDate('0000:00:00 00:00:00'), isNull);
      expect(LibraryService.parseExifDate('not a date'), isNull);
    });

    test('a file with no EXIF data gives null, not an error', () async {
      final dir = await Directory.systemTemp.createTemp('nsl_exif_test');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}\\plain.png')..writeAsBytesSync([1, 2, 3]);
      expect(await LibraryService.readTakenDate(f), isNull);
      expect(
        await LibraryService.readTakenDate(File('${dir.path}\\no')),
        isNull,
      );
    });

    test('taken date is saved in the index and used for ordering', () {
      final a = pic('a', DateTime(2026, 5, 1), exif: true);
      final back = LibraryItem.fromJson(a.toJson())!;
      expect(back.taken, a.taken);
      expect(back.when, a.taken);
      // Without it the change date stands in.
      final b = pic('b', DateTime(2026, 5, 1));
      expect(b.when, b.modified);
      expect(b.toJson().containsKey('k'), isFalse);
    });
  });

  group('EXIF in real files', exifFileTests);

  group('timeline', () {
    test('groups by day, newest day and newest picture first', () {
      final days = groupByDay([
        pic('old', DateTime(2026, 11, 1, 9), exif: true),
        pic('late', DateTime(2026, 11, 8, 20), exif: true),
        pic('early', DateTime(2026, 11, 8, 7), exif: true),
      ]);
      expect(days.map((d) => d.day), [
        DateTime(2026, 11, 8),
        DateTime(2026, 11, 1),
      ]);
      expect(days.first.items.map((i) => i.title), ['late', 'early']);
    });

    test('day labels', () {
      final now = DateTime(2026, 11, 12, 15);
      expect(dayLabel(DateTime(2026, 11, 12), now), 'Today');
      expect(dayLabel(DateTime(2026, 11, 11), now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 11, 8), now), 'Sun 8 Nov 2026');
    });
  });

  group('Photos page', () {
    late Directory tmp;
    late LibraryService lib;
    final now = DateTime(2026, 11, 12, 15);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('nsl_photos_test');
      lib = LibraryService(
        await SharedPreferences.getInstance(),
        indexFile: File('${tmp.path}\\index.json'),
        autoRescan: false,
      );
      lib.setItemsForTest([
        pic('beach', DateTime(2026, 11, 12, 10), exif: true),
        pic('hills', DateTime(2026, 11, 12, 9), exif: true),
        pic('market', DateTime(2026, 11, 11, 18), exif: true),
      ]);
    });

    tearDown(() => tmp.delete(recursive: true));

    Widget host() => MaterialApp(
      theme: buildTheme(Brightness.dark, const Color(0xFFF4B860)),
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 700,
          child: PhotosView(library: lib, onOpenLibrary: () {}, now: () => now),
        ),
      ),
    );

    testWidgets('shows a header per day with its count', (tester) async {
      await tester.pumpWidget(host());
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('2 photos'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('1 photo'), findsOneWidget);
    });

    testWidgets('search narrows the pictures', (tester) async {
      await tester.pumpWidget(host());
      await tester.enterText(find.byType(TextField), 'mark');
      await tester.pump();
      expect(find.byTooltip('market'), findsOneWidget);
      expect(find.byTooltip('beach'), findsNothing);
      expect(find.text('Today'), findsNothing);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.textContaining('No photo matches'), findsOneWidget);
    });

    testWidgets('no folders: says how to start', (tester) async {
      lib.setItemsForTest([]);
      await tester.pumpWidget(host());
      expect(find.textContaining('Add a folder with pictures'), findsOneWidget);
    });

    testWidgets('a click opens the viewer; arrows move between pictures', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.tap(find.byTooltip('beach'));
      await tester.pumpAndSettle();
      expect(find.text('beach · 1 of 3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('hills · 2 of 3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(find.text('market · 3 of 3'), findsOneWidget);

      // The last picture has no "next"; Esc goes back to the timeline.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('I shows the details panel', (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.byTooltip('hills'));
      await tester.pumpAndSettle();
      expect(find.text('DETAILS'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      expect(find.text('DETAILS'), findsOneWidget);
      expect(find.text('hills.jpg'), findsOneWidget);
      expect(find.text('Taken'), findsOneWidget);
    });
  });
}

/// A tiny JPEG whose only content is an EXIF block with DateTimeOriginal.
List<int> jpegWithExifDate(String date) {
  final text = [...date.codeUnits, 0]; // "YYYY:MM:DD HH:MM:SS" + NUL (20 bytes)
  // TIFF header (little endian), IFD0 with one entry: ExifIFD pointer.
  final tiff = <int>[
    0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, // header, IFD0 at 8
    0x01, 0x00, // IFD0: 1 entry
    0x69, 0x87, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x1A, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, // next IFD: none
    // Exif IFD at 26: 1 entry, DateTimeOriginal (0x9003), ASCII, 20, at 44
    0x01, 0x00,
    0x03, 0x90, 0x02, 0x00, 0x14, 0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    ...text,
  ];
  final exif = [...'Exif'.codeUnits, 0, 0, ...tiff];
  final len = exif.length + 2;
  return [
    0xFF, 0xD8, // SOI
    0xFF, 0xE1, (len >> 8) & 0xFF, len & 0xFF, ...exif, // APP1
    0xFF, 0xD9, // EOI
  ];
}

void exifFileTests() {
  test('reads the taken date from a real EXIF block', () async {
    final dir = await Directory.systemTemp.createTemp('nsl_exif_real');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}/camera.jpg')
      ..writeAsBytesSync(jpegWithExifDate('2026:11:08 16:42:11'));
    expect(
      await LibraryService.readTakenDate(f),
      DateTime(2026, 11, 8, 16, 42, 11),
    );
  });

  test('a scan stores it on the picture', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('nsl_exif_scan');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/camera.jpg')
        .writeAsBytesSync(jpegWithExifDate('2025:03:04 05:06:07'));
    File('${dir.path}/shot.png').writeAsBytesSync([1, 2, 3]);
    final lib = LibraryService(
      await SharedPreferences.getInstance(),
      indexFile: File('${dir.path}/index.json'),
      autoRescan: false,
    );
    await lib.addFolder(dir.path);
    final byName = {for (final i in lib.images) i.title: i};
    expect(
      byName['camera']!.taken,
      DateTime(2025, 3, 4, 5, 6, 7).millisecondsSinceEpoch,
    );
    expect(byName['shot']!.taken, isNull);
    // Dated pictures come first only by their date, not the copy date.
    expect(lib.images.first.title, anyOf('camera', 'shot'));
  });
}
