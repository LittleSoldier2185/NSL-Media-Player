import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/thumbnail_service.dart';

void main() {
  late Directory tmp;
  late Directory cache;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nsl_thumb_test');
    cache = Directory('${tmp.path}\\thumbs');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Uint8List bytes(List<int> b) => Uint8List.fromList(b);
  Future<Uint8List?> identity(Uint8List b) async => b;

  ThumbnailService make({RawImageSource? audio, RawImageSource? video}) =>
      ThumbnailService(
        dir: cache,
        audioArt: audio ?? (_) async => null,
        videoFrame: video ?? (_) async => null,
        downscale: identity,
      );

  test('music thumbnail comes from the audio source', () async {
    final s = make(audio: (_) async => bytes([1, 2, 3]));
    expect(await s.request(r'D:\a.mp3', 1).future, [1, 2, 3]);
  });

  test('video thumbnail comes from the video source', () async {
    final s = make(video: (_) async => bytes([9, 9]));
    expect(await s.request(r'D:\a.mp4', 1).future, [9, 9]);
  });

  test('second request is served from memory, not regenerated', () async {
    var calls = 0;
    final s = make(
      audio: (_) async {
        calls++;
        return bytes([1]);
      },
    );
    await s.request(r'D:\a.mp3', 1).future;
    await s.request(r'D:\a.mp3', 1).future;
    expect(calls, 1);
  });

  test('a new service reads the disk cache instead of regenerating', () async {
    await make(audio: (_) async => bytes([7, 7]))
        .request(r'D:\a.mp3', 1)
        .future;
    final again = make(audio: (_) async => throw StateError('must not run'));
    expect(await again.request(r'D:\a.mp3', 1).future, [7, 7]);
  });

  test('"no picture" is remembered on disk too', () async {
    await make(audio: (_) async => null).request(r'D:\a.mp3', 1).future;
    final again = make(audio: (_) async => throw StateError('must not run'));
    expect(await again.request(r'D:\a.mp3', 1).future, isNull);
  });

  test('a changed file (new modified time) is regenerated', () async {
    var n = 0;
    final s = make(audio: (_) async => bytes([++n]));
    expect(await s.request(r'D:\a.mp3', 1).future, [1]);
    expect(await s.request(r'D:\a.mp3', 2).future, [2]);
  });

  test('a failing source gives null instead of throwing', () async {
    final s = make(audio: (_) async => throw StateError('boom'));
    expect(await s.request(r'D:\a.mp3', 1).future, isNull);
  });

  test('a picture that cannot be shrunk gives null', () async {
    final s = ThumbnailService(
      dir: cache,
      audioArt: (_) async => bytes([1]),
      downscale: (_) async => null,
    );
    expect(await s.request(r'D:\a.mp3', 1).future, isNull);
  });

  test('keys ignore path case and depend on modified time', () {
    expect(
      ThumbnailService.keyFor(r'D:\Music\A.mp3', 5),
      ThumbnailService.keyFor(r'd:\music\a.MP3', 5),
    );
    expect(
      ThumbnailService.keyFor(r'D:\a.mp3', 5) ==
          ThumbnailService.keyFor(r'D:\a.mp3', 6),
      isFalse,
    );
    expect(
      ThumbnailService.keyFor(r'D:\a.mp3', 5) ==
          ThumbnailService.keyFor(r'D:\b.mp3', 5),
      isFalse,
    );
  });

  group('video queue', () {
    test('runs one at a time, newest request first, skips cancelled', () async {
      final started = <String>[];
      final gate = Completer<void>();
      final s = make(
        video: (path) async {
          started.add(path);
          if (path.endsWith('first.mp4')) await gate.future;
          return bytes([1]);
        },
      );

      final first = s.request(r'D:\first.mp4', 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final b = s.request(r'D:\b.mp4', 1);
      final c = s.request(r'D:\c.mp4', 1);
      final d = s.request(r'D:\d.mp4', 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Only the first is running; the rest wait.
      expect(started, [r'D:\first.mp4']);

      b.cancel(); // scrolled past before it started
      gate.complete();
      await Future.wait([first.future, c.future, d.future]);

      // Newest first (d before c), and the cancelled one never ran.
      expect(started, [r'D:\first.mp4', r'D:\d.mp4', r'D:\c.mp4']);
    });

    test('the same file requested twice is generated once', () async {
      var calls = 0;
      final s = make(
        video: (_) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return bytes([1]);
        },
      );
      final a = s.request(r'D:\a.mp4', 1);
      final b = s.request(r'D:\a.mp4', 1);
      await Future.wait([a.future, b.future]);
      expect(calls, 1);
    });

    test('cancelling one of two askers keeps the job alive', () async {
      final gate = Completer<void>();
      var ran = false;
      final s = make(
        video: (p) async {
          if (p.endsWith('block.mp4')) await gate.future;
          if (p.endsWith('shared.mp4')) ran = true;
          return bytes([1]);
        },
      );
      s.request(r'D:\block.mp4', 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final a = s.request(r'D:\shared.mp4', 1);
      final b = s.request(r'D:\shared.mp4', 1);
      a.cancel();
      gate.complete();
      expect(await b.future, [1]);
      expect(ran, isTrue);
    });
  });

  group('folderArt', () {
    test('finds cover.jpg next to the track, ignoring case', () async {
      final dir = Directory('${tmp.path}\\album')..createSync();
      File('${dir.path}\\track.mp3').writeAsBytesSync([0]);
      File('${dir.path}\\Cover.JPG').writeAsBytesSync([5, 6, 7]);
      expect(await ThumbnailService.folderArt('${dir.path}\\track.mp3'), [
        5,
        6,
        7,
      ]);
    });

    test('ignores unrelated pictures and missing folders', () async {
      final dir = Directory('${tmp.path}\\album2')..createSync();
      File('${dir.path}\\holiday.jpg').writeAsBytesSync([1]);
      expect(
        await ThumbnailService.folderArt('${dir.path}\\track.mp3'),
        isNull,
      );
      expect(
        await ThumbnailService.folderArt('${tmp.path}\\nope\\x.mp3'),
        isNull,
      );
    });
  });

  test('cache size is counted and clearCache empties it', () async {
    final s = make(audio: (_) async => bytes(List.filled(100, 1)));
    await s.request(r'D:\a.mp3', 1).future;
    await s.request(r'D:\b.mp3', 1).future;
    expect(await s.cacheSizeBytes(), 200);
    await s.clearCache();
    expect(await s.cacheSizeBytes(), 0);
    // Regenerates after clearing.
    var calls = 0;
    final s2 = make(
      audio: (_) async {
        calls++;
        return bytes([1]);
      },
    );
    await s2.request(r'D:\a.mp3', 1).future;
    expect(calls, 1);
  });
}
