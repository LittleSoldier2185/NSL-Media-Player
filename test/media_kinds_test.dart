import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/library_service.dart';
import 'package:nsl_media_player/services/media_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('kindOf sorts files into the four kinds', () {
    expect(kindOf(r'C:\m\a.MP3'), MediaKind.audio);
    expect(kindOf('clip.mkv'), MediaKind.video);
    expect(kindOf('photo.JPG'), MediaKind.image);
    expect(kindOf('scan.webp'), MediaKind.image);
    expect(kindOf('book.pdf'), MediaKind.pdf);
    expect(kindOf('notes.txt'), isNull);
    expect(kindOf('noextension'), isNull);
  });

  test('pictures and PDFs are library files but never playable media', () {
    expect(isLibraryFile('a.jpg'), isTrue);
    expect(isLibraryFile('b.pdf'), isTrue);
    expect(isLibraryFile('c.mp3'), isTrue);
    expect(isLibraryFile('d.txt'), isFalse);
    // Opening a folder or dropping files into the player must skip them.
    expect(isSupportedMedia('a.jpg'), isFalse);
    expect(isSupportedMedia('b.pdf'), isFalse);
    expect(firstMediaArg(['a.jpg', 'b.pdf']), isNull);
  });

  group('library keeps all four kinds', () {
    late Directory tmp;
    late Directory folder;
    late File index;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('nsl_kinds_test');
      folder = Directory('${tmp.path}\\stuff')..createSync();
      index = File('${tmp.path}\\index.json');
      for (final n in ['song.mp3', 'clip.mp4', 'a.jpg', 'b.png', 'book.pdf']) {
        File('${folder.path}\\$n').writeAsStringSync('x');
      }
      // b.png is newer than a.jpg.
      File('${folder.path}\\a.jpg').setLastModifiedSync(DateTime(2026, 1, 1));
      File('${folder.path}\\b.png').setLastModifiedSync(DateTime(2026, 6, 1));
    });

    tearDown(() => tmp.delete(recursive: true));

    Future<LibraryService> make({bool autoRescan = true}) async =>
        LibraryService(
          await SharedPreferences.getInstance(),
          indexFile: index,
          autoRescan: autoRescan,
        );

    test('pictures and PDFs are counted but kept out of items', () async {
      final lib = await make();
      await lib.addFolder(folder.path);
      expect(lib.items.map((i) => i.title), unorderedEquals(['song', 'clip']));
      expect(lib.musicCount, 1);
      expect(lib.videoCount, 1);
      expect(lib.imageCount, 2);
      expect(lib.bookCount, 1);
      expect(lib.images.map((i) => i.title), ['b', 'a']); // newest first
      expect(lib.books.single.title, 'book');
      expect(lib.query().every((i) => i.isPlayable), isTrue);
    });

    test('they are saved in the index and survive a restart', () async {
      final first = await make();
      await first.addFolder(folder.path);
      final second = await make(autoRescan: false);
      expect(second.imageCount, 2);
      expect(second.bookCount, 1);
      expect(second.items.length, 2);
    });

    test('removing the folder drops its pictures and books too', () async {
      final lib = await make();
      await lib.addFolder(folder.path);
      await lib.removeFolder(lib.folders.single);
      expect(lib.imageCount, 0);
      expect(lib.bookCount, 0);
    });

    test('an index from before the new kinds is rescanned once', () async {
      // Old index: music and video only. Folder already saved.
      index.writeAsStringSync(
        jsonEncode([
          {'p': '${folder.path}\\song.mp3', 't': 'song', 'm': 1},
        ]),
      );
      SharedPreferences.setMockInitialValues({
        'libraryFolders': [folder.path],
      });
      final lib = await make();
      expect(lib.imageCount, 0); // not known yet
      for (var i = 0; i < 50 && lib.imageCount == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(lib.imageCount, 2);
      expect(lib.bookCount, 1);
      // Let the scan (and the picture comparison after it) finish.
      for (var i = 0; i < 100 && (lib.scanning || lib.hashing); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      // Done once: a second start does not scan again.
      final again = await make(autoRescan: true);
      expect(again.scanning, isFalse);
      expect(again.imageCount, 2);
    });

    test('the mini player process can skip the automatic rescan', () async {
      SharedPreferences.setMockInitialValues({
        'libraryFolders': [folder.path],
      });
      final lib = await make(autoRescan: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(lib.imageCount, 0);
      expect(lib.scanning, isFalse);
    });
  });
}
