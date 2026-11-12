import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/library_service.dart';
import 'package:nsl_media_player/services/playlist_service.dart';
import 'package:nsl_media_player/ui/photo_viewer.dart';
import 'package:nsl_media_player/ui/photos_view.dart';
import 'package:nsl_media_player/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

LibraryItem pic(String dir, String name, DateTime when) => LibraryItem(
  path: 'C:\\pictures\\$dir\\$name.jpg',
  title: name,
  modified: when.millisecondsSinceEpoch,
);

/// A test with a desktop-sized window (the default test window is 800 x 600).
void viewTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await body(tester);
    });

void main() {
  group('folder albums', () {
    test('every folder with pictures is an album, newest first', () {
      final folders = folderAlbums([
        pic('trip', 'a', DateTime(2026, 1, 1)),
        pic('Trip', 'b', DateTime(2026, 3, 1)), // same folder, other case
        pic('home', 'c', DateTime(2026, 5, 1)),
      ]);
      expect(folders.map((f) => f.name), ['home', 'trip']);
      expect(folders.last.items.map((i) => i.title), ['b', 'a']);
      expect(folders.last.dir.toLowerCase(), r'c:\pictures\trip');
    });

    test('no pictures, no folders', () {
      expect(folderAlbums([]), isEmpty);
    });
  });

  group('albums are stored like playlists, in their own file', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('nsl_album_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('default name and persistence', () {
      final file = File('${tmp.path}/photo_albums.json');
      final s = PlaylistService(file: file, defaultName: 'New album');
      expect(s.create('  ').name, 'New album');
      expect(s.create('Trip', ['a.jpg', 'b.jpg']).paths.length, 2);
      final again = PlaylistService(file: file, defaultName: 'New album');
      expect(again.all.map((a) => a.name), ['New album', 'Trip']);
    });
  });

  group('Photos page: albums, folders, slideshow', () {
    late Directory tmp;
    late LibraryService lib;
    late PlaylistService albums;
    final now = DateTime(2026, 11, 12, 15);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('nsl_photoalbum_ui');
      lib = LibraryService(
        await SharedPreferences.getInstance(),
        indexFile: File('${tmp.path}/index.json'),
        autoRescan: false,
      );
      albums = PlaylistService(
        file: File('${tmp.path}/albums.json'),
        defaultName: 'New album',
      );
      lib.setItemsForTest([
        pic('trip', 'beach', DateTime(2026, 11, 12, 10)),
        pic('trip', 'hills', DateTime(2026, 11, 12, 9)),
        pic('home', 'cat', DateTime(2026, 11, 11, 18)),
      ]);
    });

    tearDown(() => tmp.delete(recursive: true));

    Widget host() => MaterialApp(
      theme: buildTheme(Brightness.dark, const Color(0xFFF4B860)),
      home: Scaffold(
        body: SizedBox(
          width: 1300,
          height: 1000,
          child: PhotosView(
            library: lib,
            albums: albums,
            onOpenLibrary: () {},
            now: () => now,
          ),
        ),
      ),
    );

    viewTest('Folders tab lists folders; one opens with its pictures', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.tap(find.text('Folders'));
      await tester.pump();
      expect(find.text('trip'), findsOneWidget);
      expect(find.text('2 photos'), findsOneWidget);
      expect(find.text('home'), findsOneWidget);

      await tester.tap(find.text('trip'));
      await tester.pump();
      expect(find.byTooltip('beach'), findsOneWidget);
      expect(find.byTooltip('cat'), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      expect(find.text('home'), findsOneWidget);
    });

    viewTest('Albums tab says how to start when there are none', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.tap(find.text('Albums'));
      await tester.pump();
      expect(find.textContaining('No albums yet'), findsOneWidget);
    });

    viewTest('select pictures and add them to a new album', (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.text('Select'));
      await tester.pump();
      expect(find.text('Pick pictures'), findsOneWidget);

      await tester.tap(find.byTooltip('beach'));
      await tester.tap(find.byTooltip('cat'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.text('Add to album'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New album…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Favourites');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(albums.all.single.name, 'Favourites');
      expect(albums.all.single.paths.length, 2);
      // Selection mode ended.
      expect(find.text('Pick pictures'), findsNothing);

      await tester.tap(find.text('Albums'));
      await tester.pump();
      expect(find.text('Favourites'), findsOneWidget);
      expect(find.text('2 photos'), findsOneWidget);
    });

    viewTest('open an album, remove a picture, rename, delete', (tester) async {
      final a = albums.create('Trip', [
        'C:\\pictures\\trip\\beach.jpg',
        'C:\\pictures\\trip\\hills.jpg',
      ]);
      await tester.pumpWidget(host());
      await tester.tap(find.text('Albums'));
      await tester.pump();
      await tester.tap(find.text('Trip'));
      await tester.pump();
      expect(find.byTooltip('beach'), findsOneWidget);

      // Remove one picture from the album (the file stays).
      await tester.tap(find.text('Select'));
      await tester.pump();
      await tester.tap(find.byTooltip('hills'));
      await tester.pump();
      await tester.tap(find.text('Remove from album'));
      await tester.pump();
      expect(albums.byId(a.id)!.paths, ['C:\\pictures\\trip\\beach.jpg']);
      expect(lib.imageCount, 3);

      // Rename.
      await tester.tap(find.byTooltip('Album'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Holiday');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(albums.byId(a.id)!.name, 'Holiday');

      // Delete: back to the (now empty) list; pictures are untouched.
      await tester.tap(find.byTooltip('Album'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete album'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(albums.all, isEmpty);
      expect(find.textContaining('No albums yet'), findsOneWidget);
      expect(lib.imageCount, 3);
    });

    viewTest('viewer: slideshow steps on its own, wraps, pauses', (
      tester,
    ) async {
      final items = [
        pic('trip', 'one', DateTime(2026, 1, 3)),
        pic('trip', 'two', DateTime(2026, 1, 2)),
        pic('trip', 'three', DateTime(2026, 1, 1)),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark, const Color(0xFFF4B860)),
          home: PhotoViewerPage(items: items, albums: albums, slideshow: true),
        ),
      );
      await tester.pump(); // post-frame: slideshow starts
      expect(find.text('one · 1 of 3'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      expect(find.text('two · 2 of 3'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('three · 3 of 3'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // wraps to the start
      expect(find.text('one · 1 of 3'), findsOneWidget);

      // Space pauses: nothing moves any more.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('one · 1 of 3'), findsOneWidget);

      // A key of your own still moves, and does not start it again.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('two · 2 of 3'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('two · 2 of 3'), findsOneWidget);
    });

    viewTest('viewer: moving by hand restarts the interval', (tester) async {
      final items = [
        pic('trip', 'one', DateTime(2026, 1, 3)),
        pic('trip', 'two', DateTime(2026, 1, 2)),
        pic('trip', 'three', DateTime(2026, 1, 1)),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark, const Color(0xFFF4B860)),
          home: PhotoViewerPage(items: items, slideshow: true),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // by hand
      await tester.pump();
      expect(find.text('two · 2 of 3'), findsOneWidget);
      // 4 s later the old timer would have fired; the new one has not yet.
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('two · 2 of 3'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('three · 3 of 3'), findsOneWidget);
    });
  });
}
