import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/library_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  late Directory media;
  late File index;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('nsl_lib_test');
    media = Directory('${tmp.path}\\media')..createSync();
    index = File('${tmp.path}\\index.json');
    // Files with no valid tags: the service must still list them by file name.
    for (final n in [
      'beta.mp3',
      'Alpha.flac',
      'clip.mp4',
      'notes.txt', // not media: ignored
    ]) {
      File('${media.path}\\$n').writeAsStringSync('not real media');
    }
    Directory('${media.path}\\sub').createSync();
    File('${media.path}\\sub\\gamma.wav').writeAsStringSync('x');
  });

  tearDown(() => tmp.delete(recursive: true));

  Future<LibraryService> make() async =>
      LibraryService(await SharedPreferences.getInstance(), indexFile: index);

  test('scan finds supported media recursively and ignores the rest', () async {
    final lib = await make();
    await lib.addFolder(media.path);
    expect(lib.items.length, 4);
    expect(lib.musicCount, 3);
    expect(lib.videoCount, 1);
    expect(lib.scanning, isFalse);
  });

  test('untagged files fall back to the file name without extension', () async {
    final lib = await make();
    await lib.addFolder(media.path);
    expect(lib.items.map((i) => i.title), containsAll(['beta', 'Alpha']));
  });

  test('query filters by text and type, sorts case-insensitively', () async {
    final lib = await make();
    await lib.addFolder(media.path);
    expect(lib.query().map((i) => i.title), ['Alpha', 'beta', 'clip', 'gamma']);
    expect(lib.query(video: true).map((i) => i.title), ['clip']);
    expect(lib.query(video: false).length, 3);
    expect(lib.query(query: 'ALP').map((i) => i.title), ['Alpha']);
    expect(lib.query(query: 'zzz'), isEmpty);
  });

  test('index is cached and reloaded, folders persist', () async {
    final lib = await make();
    await lib.addFolder(media.path);
    expect(index.existsSync(), isTrue);

    final again = await make();
    expect(again.folders, [media.path]);
    expect(again.items.length, 4);
  });

  test('removeFolder drops that folder\'s items', () async {
    final lib = await make();
    await lib.addFolder(media.path);
    await lib.removeFolder(media.path);
    expect(lib.items, isEmpty);
    expect(lib.folders, isEmpty);
  });

  group('multiple folders', () {
    late Directory other;
    setUp(() {
      other = Directory('${tmp.path}\\media2')..createSync();
      File('${other.path}\\zeta.mp3').writeAsStringSync('x');
    });

    test('several folders are saved together and filterable', () async {
      final lib = await make();
      await lib.addFolder(media.path);
      await lib.addFolder(other.path);
      expect(lib.folders.length, 2);
      expect(lib.items.length, 5);
      expect(lib.countIn(media.path), 4);
      expect(lib.countIn(other.path), 1);
      expect(lib.query(folder: other.path).map((i) => i.title), ['zeta']);
    });

    test('"media" does not match "media2" (whole path segments only)', () {
      expect(LibraryService.isUnder('C:\\Music2\\a.mp3', 'C:\\Music'), isFalse);
      expect(LibraryService.isUnder('C:\\Music\\a.mp3', 'C:\\Music'), isTrue);
      expect(
        LibraryService.isUnder('c:\\MUSIC\\x\\a.mp3', 'C:\\Music\\'),
        isTrue,
      );
    });

    test('adding the same folder twice is refused', () async {
      final lib = await make();
      expect(await lib.addFolder(media.path), isTrue);
      expect(await lib.addFolder('${media.path}\\'), isFalse);
      expect(lib.folders.length, 1);
    });

    test('nested folders do not list files twice', () async {
      final lib = await make();
      await lib.addFolder(media.path);
      await lib.addFolder('${media.path}\\sub');
      expect(lib.items.length, 4);
    });

    test(
      'removing a parent keeps files a nested folder still covers',
      () async {
        final lib = await make();
        await lib.addFolder(media.path);
        await lib.addFolder('${media.path}\\sub');
        await lib.removeFolder(media.path);
        expect(lib.items.map((i) => i.title), ['gamma']);
      },
    );

    test('folderName gives the last segment', () {
      expect(LibraryService.folderName('C:\\Users\\me\\Music'), 'Music');
      expect(LibraryService.folderName('C:\\Users\\me\\Music\\'), 'Music');
    });
  });

  test('rescan picks up new files', () async {
    final lib = await make();
    await lib.addFolder(media.path);
    File('${media.path}\\delta.ogg').writeAsStringSync('x');
    await lib.scan();
    expect(lib.items.length, 5);
  });
}
