import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/playlist_service.dart';

void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nsl_pl_test');
    file = File('${tmp.path}\\playlists.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  PlaylistService make() => PlaylistService(file: file);

  test('a playlist can mix files from different folders', () {
    final s = make();
    final p = s.create('Mix', [
      r'D:\Music\a.mp3',
      r'E:\Movies\b.mp4',
      r'F:\Podcasts\c.mp3',
    ]);
    expect(p.paths.length, 3);
    expect(s.byId(p.id)!.paths[1], r'E:\Movies\b.mp4');
  });

  test('create drops duplicate paths, keeping order', () {
    final s = make();
    final p = s.create('X', [r'D:\a.mp3', r'D:\b.mp3', r'd:\A.MP3']);
    expect(p.paths, [r'D:\a.mp3', r'D:\b.mp3']);
  });

  test('addPaths skips files already present and reports the count', () {
    final s = make();
    final p = s.create('X', [r'D:\a.mp3']);
    expect(s.addPaths(p.id, [r'D:\a.mp3', r'E:\b.mp3', r'E:\c.mp3']), 2);
    expect(p.paths, [r'D:\a.mp3', r'E:\b.mp3', r'E:\c.mp3']);
    expect(s.addPaths(p.id, [r'E:\b.mp3']), 0);
    expect(s.addPaths('missing-id', [r'E:\b.mp3']), 0);
  });

  test('names stay unique and blank names get a default', () {
    final s = make();
    expect(s.create('Gym').name, 'Gym');
    expect(s.create('gym').name, 'gym (2)');
    expect(s.create('Gym').name, 'Gym (3)');
    expect(s.create('   ').name, 'New playlist');
  });

  test('rename may keep its own name but not take another', () {
    final s = make();
    final a = s.create('A');
    final b = s.create('B');
    s.rename(a.id, 'A');
    expect(a.name, 'A');
    s.rename(b.id, 'a');
    expect(b.name, 'a (2)');
  });

  test('delete and removeAt', () {
    final s = make();
    final p = s.create('X', [r'D:\a.mp3', r'D:\b.mp3', r'D:\c.mp3']);
    s.removeAt(p.id, 1);
    expect(p.paths, [r'D:\a.mp3', r'D:\c.mp3']);
    s.removeAt(p.id, 9); // out of range: ignored
    expect(p.paths.length, 2);
    s.delete(p.id);
    expect(s.all, isEmpty);
  });

  test('move puts the item at its final index', () {
    final s = make();
    final p = s.create('X', ['a', 'b', 'c', 'd']);
    s.move(p.id, 0, 2); // a ends up third
    expect(p.paths, ['b', 'c', 'a', 'd']);
    s.move(p.id, 3, 0); // d to the front
    expect(p.paths, ['d', 'b', 'c', 'a']);
    s.move(p.id, 1, 3); // b to the end
    expect(p.paths, ['d', 'c', 'a', 'b']);
    s.move(p.id, 2, 99); // out-of-range target clamps to the end
    expect(p.paths, ['d', 'c', 'b', 'a']);
  });

  test('playlists persist across restarts', () {
    final s = make();
    final p = s.create('Keep', [r'D:\a.mp3', r'E:\b.mp4']);
    s.rename(p.id, 'Kept');

    final again = make();
    expect(again.all.length, 1);
    expect(again.all.first.name, 'Kept');
    expect(again.all.first.paths, [r'D:\a.mp3', r'E:\b.mp4']);
  });

  test('a corrupt file starts empty instead of crashing', () {
    file.writeAsStringSync('{not json');
    expect(make().all, isEmpty);
  });

  test('notifies listeners on change', () {
    final s = make();
    var n = 0;
    s.addListener(() => n++);
    final p = s.create('X');
    s.addPaths(p.id, ['a']);
    s.delete(p.id);
    expect(n, 3);
  });
}
