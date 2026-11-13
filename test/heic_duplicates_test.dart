import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/heic_converter.dart';
import 'package:nsl_media_player/services/library_service.dart';
import 'package:nsl_media_player/services/media_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nsl_11d_test');
  });
  tearDown(() => tmp.delete(recursive: true));

  group('HEIC', () {
    test('counts as a picture', () {
      expect(kindOf('C:\\a\\IMG_1.HEIC'), MediaKind.image);
      expect(kindOf('C:\\a\\IMG_1.heif'), MediaKind.image);
      expect(HeicConverter.isHeic('x.HEIC'), isTrue);
      expect(HeicConverter.isHeic('x.jpg'), isFalse);
    });

    test('ordinary pictures are used as they are', () async {
      final c = HeicConverter(
        dir: Directory('${tmp.path}\\heic'),
        run: (_, _) async => fail('must not convert a jpg'),
      );
      expect(await c.viewable('C:\\a\\b.jpg'), 'C:\\a\\b.jpg');
      expect(c.cachedPath('C:\\a\\b.png'), 'C:\\a\\b.png');
    });

    test('converts once, then serves the cached JPEG', () async {
      final src = File('${tmp.path}\\p.heic')..writeAsBytesSync([1, 2, 3]);
      var runs = 0;
      final c = HeicConverter(
        dir: Directory('${tmp.path}\\heic'),
        run: (s, d) async {
          runs++;
          File(d).writeAsBytesSync([0xFF, 0xD8, 0xFF]);
          return true;
        },
      );
      expect(c.cachedPath(src.path), isNull);
      final a = await c.viewable(src.path);
      expect(a, endsWith('.jpg'));
      expect(File(a!).existsSync(), isTrue);
      expect(await c.viewable(src.path), a);
      expect(c.cachedPath(src.path), a);
      expect(runs, 1);
      // The original is untouched.
      expect(src.readAsBytesSync(), [1, 2, 3]);
    });

    test('a failed conversion gives null and leaves nothing behind', () async {
      final src = File('${tmp.path}\\bad.heic')..writeAsBytesSync([1]);
      final c = HeicConverter(
        dir: Directory('${tmp.path}\\heic'),
        run: (s, d) async {
          File(d).writeAsBytesSync([9]); // half-written output
          return false;
        },
      );
      expect(await c.viewable(src.path), isNull);
      expect(c.cachedPath(src.path), isNull);
      expect(await c.cacheSizeBytes(), 0);
    });

    test('a missing file gives null', () async {
      final c = HeicConverter(
        dir: Directory('${tmp.path}\\heic'),
        run: (_, _) async => true,
      );
      expect(await c.viewable('${tmp.path}\\nope.heic'), isNull);
    });
  });

  group('duplicate pictures', () {
    Future<LibraryService> libraryWith(List<File> files) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lib = LibraryService(
        prefs,
        indexFile: File('${tmp.path}\\index.json'),
        autoRescan: false,
      );
      lib.setItemsForTest([
        for (final f in files)
          LibraryItem(
            path: f.path,
            title: fileNameOf(f.path),
            modified: f.lastModifiedSync().millisecondsSinceEpoch,
            size: f.lengthSync(),
          ),
      ]);
      return lib;
    }

    File make(String name, List<int> bytes) =>
        File('${tmp.path}\\$name.jpg')..writeAsBytesSync(bytes);

    test('same contents are found, same size but different are not', () async {
      final a = make('a', [1, 2, 3, 4]);
      final b = make('b_copy', [1, 2, 3, 4]);
      final c = make('c_samesize', [9, 9, 9, 9]);
      final d = make('d_unique', [1, 2]);
      final lib = await libraryWith([a, b, c, d]);
      await lib.findDuplicates();
      expect(lib.duplicates, hasLength(1));
      expect(lib.duplicateCount, 1);
      // Only the candidates with a twin of the same size were read.
      final hashed = lib.images.where((i) => i.hash != null).length;
      expect(hashed, 3);
      expect(lib.images.firstWhere((i) => i.title == 'd_unique.jpg').hash, isNull);
    });

    test('the oldest copy is kept; the others are hidden on request', () async {
      final a = make('a', [5, 5, 5]);
      final b = make('b', [5, 5, 5]);
      final lib = await libraryWith([a, b]);
      // a is older.
      lib.setItemsForTest([
        LibraryItem(
          path: a.path,
          title: 'a',
          modified: 1000,
          size: 3,
        ),
        LibraryItem(
          path: b.path,
          title: 'b',
          modified: 2000,
          size: 3,
        ),
      ]);
      await lib.findDuplicates();
      expect(lib.duplicatePaths, {b.path.toLowerCase()});
      expect(lib.hideDuplicates, isTrue);
      expect(lib.visibleImages.map((i) => i.title), ['a']);
      lib.hideDuplicates = false;
      expect(lib.visibleImages, hasLength(2));
      // Nothing is deleted.
      expect(a.existsSync() && b.existsSync(), isTrue);
    });

    test('hashes are saved in the index and reused', () async {
      final a = make('a', [7, 7]);
      final b = make('b', [7, 7]);
      final lib = await libraryWith([a, b]);
      await lib.findDuplicates();
      final json = File('${tmp.path}\\index.json').readAsStringSync();
      expect(json, contains('"h"'));
      expect(json, contains('"z"'));
      final back = LibraryItem.fromJson(
        lib.images.first.toJson(),
      );
      expect(back!.size, 2);
      expect(back.hash, lib.images.first.hash);
    });

    test('an unreadable file does not break the search', () async {
      final a = make('a', [1, 1]);
      final b = make('b', [1, 1]);
      final lib = await libraryWith([a, b]);
      b.deleteSync();
      await lib.findDuplicates();
      expect(lib.duplicates, isEmpty);
    });
  });
}
