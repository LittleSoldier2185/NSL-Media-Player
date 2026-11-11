import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/library_service.dart';
import 'package:nsl_media_player/services/random_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

LibraryItem item(
  String path, {
  String artist = '',
  String album = '',
  int modified = 1,
}) => LibraryItem(
  path: path,
  title: path,
  artist: artist,
  album: album,
  modified: modified,
);

void main() {
  modelTests();
  group('pickRandomVideos', () {
    final videos = [for (var i = 1; i <= 6; i++) item('D:\\v\\clip$i.mp4')];
    final songs = [item('D:\\m\\a.mp3'), item('D:\\m\\b.flac')];

    test('only picks videos, never songs', () {
      final r = pickRandomVideos(
        [...videos, ...songs],
        played: (_) => false,
        count: 10,
        rng: Random(1),
      );
      expect(r.items.length, 6);
      expect(r.items.every((i) => i.isVideo), isTrue);
    });

    test('gives distinct videos', () {
      final r = pickRandomVideos(
        videos,
        played: (_) => false,
        count: 3,
        rng: Random(2),
      );
      expect({for (final i in r.items) i.path}.length, 3);
    });

    test('only unwatched skips played files', () {
      final seen = {for (final v in videos.take(4)) v.path};
      for (var seed = 0; seed < 30; seed++) {
        final r = pickRandomVideos(
          videos,
          played: seen.contains,
          count: 2,
          rng: Random(seed),
        );
        expect(r.fellBack, isFalse);
        expect(r.items.every((i) => !seen.contains(i.path)), isTrue);
      }
    });

    test(
      'falls back to all videos once everything is watched, and says so',
      () {
        final r = pickRandomVideos(
          videos,
          played: (_) => true,
          count: 2,
          rng: Random(3),
        );
        expect(r.fellBack, isTrue);
        expect(r.items.length, 2);
      },
    );

    test('with onlyUnwatched off, played files are fair game', () {
      final r = pickRandomVideos(
        videos,
        played: (_) => true,
        count: 6,
        onlyUnwatched: false,
        rng: Random(4),
      );
      expect(r.fellBack, isFalse);
      expect(r.items.length, 6);
    });

    test('rolling again avoids what was just shown when there is more', () {
      final first = pickRandomVideos(
        videos,
        played: (_) => false,
        count: 3,
        rng: Random(5),
      );
      final shown = {for (final i in first.items) i.path};
      for (var seed = 0; seed < 20; seed++) {
        final next = pickRandomVideos(
          videos,
          played: (_) => false,
          count: 3,
          avoid: shown,
          rng: Random(seed),
        );
        expect(next.items.any((i) => shown.contains(i.path)), isFalse);
      }
    });

    test('when nothing else is left, repeating is allowed', () {
      final one = [item('D:\\v\\only.mp4')];
      final r = pickRandomVideos(
        one,
        played: (_) => false,
        avoid: {'D:\\v\\only.mp4'},
        rng: Random(6),
      );
      expect(r.items.single.path, 'D:\\v\\only.mp4');
    });

    test('empty library gives nothing', () {
      final r = pickRandomVideos(
        const <LibraryItem>[],
        played: (_) => false,
        rng: Random(7),
      );
      expect(r.items, isEmpty);
      expect(r.fellBack, isFalse);
    });

    test('the same seed gives the same pick', () {
      List<String> run() => pickRandomVideos(
        videos,
        played: (_) => false,
        count: 3,
        rng: Random(42),
      ).items.map((i) => i.path).toList();
      expect(run(), run());
    });
  });

  group('albums', () {
    late LibraryService lib;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      lib = LibraryService(await SharedPreferences.getInstance());
    });

    test('groups songs by album and folder, in file-name order', () {
      lib.setItemsForTest([
        item(
          r'D:\Music\Neon\02 Rain.mp3',
          artist: 'Neon Coast',
          album: 'Midnight Drive',
          modified: 5,
        ),
        item(
          r'D:\Music\Neon\01 Drive.mp3',
          artist: 'Neon Coast',
          album: 'Midnight Drive',
          modified: 7,
        ),
        item(
          r'D:\Music\Aria\01 Hour.mp3',
          artist: 'Aria Lane',
          album: 'Blue Hour',
          modified: 3,
        ),
      ]);
      final a = lib.albums();
      expect(a.map((x) => x.name), [
        'Midnight Drive',
        'Blue Hour',
      ]); // newest first
      expect(a.first.tracks.map((t) => t.path), [
        r'D:\Music\Neon\01 Drive.mp3',
        r'D:\Music\Neon\02 Rain.mp3',
      ]);
      expect(a.first.artist, 'Neon Coast');
      expect(a.first.cover.path, r'D:\Music\Neon\01 Drive.mp3');
    });

    test('the same album name in different folders stays separate', () {
      lib.setItemsForTest([
        item(r'D:\A\1.mp3', artist: 'X', album: 'Greatest Hits'),
        item(r'D:\B\1.mp3', artist: 'Y', album: 'Greatest Hits'),
      ]);
      expect(lib.albums().length, 2);
    });

    test('different artists on one album become Various artists', () {
      lib.setItemsForTest([
        item(r'D:\C\1.mp3', artist: 'X', album: 'Mix'),
        item(r'D:\C\2.mp3', artist: 'Y', album: 'Mix'),
      ]);
      expect(lib.albums().single.artist, 'Various artists');
    });

    test('songs without an album tag, and videos, are not in any album', () {
      lib.setItemsForTest([
        item(r'D:\C\1.mp3'),
        item(r'D:\C\clip.mp4', album: 'Odd'),
        item(r'D:\C\2.mp3', album: '   '),
      ]);
      expect(lib.albums(), isEmpty);
    });

    test('the result is cached until the index changes', () {
      lib.setItemsForTest([item(r'D:\C\1.mp3', album: 'One')]);
      final first = lib.albums();
      expect(identical(lib.albums(), first), isTrue);
      lib.setItemsForTest([
        item(r'D:\C\1.mp3', album: 'One'),
        item(r'D:\D\1.mp3', album: 'Two'),
      ]);
      expect(lib.albums().length, 2);
    });

    test('artist count ignores blanks, case and videos', () {
      lib.setItemsForTest([
        item(r'D:\1.mp3', artist: 'Sora'),
        item(r'D:\2.mp3', artist: 'sora '),
        item(r'D:\3.mp3', artist: 'Aria Lane'),
        item(r'D:\4.mp3'),
        item(r'D:\5.mp4', artist: 'Someone'),
      ]);
      expect(lib.artistCount, 2);
    });
  });
}

void modelTests() {
  group('RandomVideoModel', () {
    final lib = [
      for (var i = 1; i <= 8; i++) item('D:\v\clip$i.mp4'),
      item('D:\m\song.mp3'),
    ];

    RandomVideoModel make({Set<String> played = const {}, Random? rng}) =>
        RandomVideoModel(
          items: () => lib,
          played: () => played,
          rng: rng ?? Random(1),
        );

    test('picks stay the same until rolled', () {
      final m = make()..ensure();
      final first = m.picks.map((p) => p.path).toList();
      m.ensure();
      m.ensure();
      expect(m.picks.map((p) => p.path), first);
      expect(first.length, RandomVideoModel.pickCount);
    });

    test('rolling again notifies and shows new videos', () {
      final m = make()..ensure();
      final before = {for (final p in m.picks) p.path};
      var notified = 0;
      m.addListener(() => notified++);
      m.roll();
      expect(notified, 1);
      expect(m.picks.any((p) => before.contains(p.path)), isFalse);
    });

    test('the unwatched filter re-picks and respects played files', () {
      final played = {for (var i = 1; i <= 6; i++) 'd:\v\clip$i.mp4'};
      final m = make(played: played)..ensure();
      expect(
        m.picks.every((p) => !played.contains(p.path.toLowerCase())),
        isTrue,
      );
      m.setOnlyUnwatched(false);
      expect(m.onlyUnwatched, isFalse);
      expect(m.picks.length, 3);
    });

    test('falls back and says so when all are played', () {
      final played = {for (final v in lib) v.path.toLowerCase()};
      final m = make(played: played)..ensure();
      expect(m.fellBack, isTrue);
      expect(m.picks, isNotEmpty);
    });

    test('knows when the library has no videos', () {
      final m = RandomVideoModel(
        items: () => [item('D:\m\song.mp3')],
        played: () => {},
      )..ensure();
      expect(m.noVideos, isTrue);
      expect(m.picks, isEmpty);
    });
  });
}
