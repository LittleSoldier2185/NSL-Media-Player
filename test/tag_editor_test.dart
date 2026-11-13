import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/tag_editor.dart';

import 'tag_test_support.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('nsl_tags'));
  tearDown(() => tmp.delete(recursive: true));

  test('which formats can be edited', () {
    expect(canEditTags('a.MP3'), isTrue);
    expect(canEditTags('a.flac'), isTrue);
    expect(canEditTags('a.ogg'), isFalse);
    expect(canEditTags('a.mp4'), isFalse);
  });

  test('cover type is found from the bytes', () {
    expect(coverMimeType(jpeg()), 'image/jpeg');
    expect(coverMimeType(png()), 'image/png');
    expect(
      coverMimeType(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9])),
      isNull,
    );
  });

  test('reads the tags of a file', () async {
    final f = makeMp3(tmp, 'a.mp3');
    final v = await readTagValues(f.path);
    expect(v.title, 'Old title');
    expect(v.artist, 'Old artist');
    expect(v.album, 'Old album');
    expect(v.cover, isNull);
  });

  test('changes title, artist and album, and leaves no safety copy', () async {
    final f = makeMp3(tmp, 'a.mp3');
    await writeTagValues(
      f.path,
      const TagEdit(
        title: 'New title',
        artist: 'New artist',
        album: 'New album',
      ),
    );
    final m = readMetadata(f, getImage: true);
    expect(m.title, 'New title');
    expect(m.artist, 'New artist');
    expect(m.album, 'New album');
    expect(File('${f.path}.nslbak').existsSync(), isFalse);
  });

  test('a field left null is not touched', () async {
    final f = makeMp3(tmp, 'a.mp3');
    await writeTagValues(f.path, const TagEdit(artist: 'Only artist'));
    final v = await readTagValues(f.path);
    expect(v.title, 'Old title');
    expect(v.artist, 'Only artist');
    expect(v.album, 'Old album');
  });

  test('Thai text survives', () async {
    final f = makeMp3(tmp, 'a.mp3');
    await writeTagValues(
      f.path,
      const TagEdit(title: 'เพลงใหม่', artist: 'ศิลปิน'),
    );
    final v = await readTagValues(f.path);
    expect(v.title, 'เพลงใหม่');
    expect(v.artist, 'ศิลปิน');
  });

  test('adds a cover, then removes it', () async {
    final f = makeMp3(tmp, 'a.mp3');
    final pic = jpeg(500);
    await writeTagValues(f.path, TagEdit(cover: pic));
    var v = await readTagValues(f.path);
    expect(v.cover, isNotNull);
    expect(v.cover!.length, pic.length);
    expect(v.title, 'Old title', reason: 'other tags kept');

    await writeTagValues(f.path, const TagEdit(removeCover: true));
    v = await readTagValues(f.path);
    expect(v.cover, isNull);
  });

  test('a PNG cover is accepted', () async {
    final f = makeMp3(tmp, 'a.mp3');
    await writeTagValues(f.path, TagEdit(cover: png()));
    expect((await readTagValues(f.path)).cover!.length, png().length);
  });

  test('refuses what cannot be edited, without touching the file', () async {
    final f = File('${tmp.path}/a.ogg')..writeAsBytesSync([1, 2, 3]);
    await expectLater(
      writeTagValues(f.path, const TagEdit(title: 'x')),
      throwsA(isA<TagEditException>()),
    );
    expect(f.readAsBytesSync(), [1, 2, 3]);

    final mp3 = makeMp3(tmp, 'b.mp3');
    await expectLater(
      writeTagValues(
        mp3.path,
        TagEdit(cover: Uint8List.fromList(List.filled(20, 1))),
      ),
      throwsA(isA<TagEditException>()),
    );
  });

  test('a missing file is reported', () async {
    await expectLater(
      writeTagValues('${tmp.path}/nope.mp3', const TagEdit(title: 'x')),
      throwsA(isA<TagEditException>()),
    );
  });

  test('a failed edit puts the original back', () async {
    // Not a real song: the writer cannot cope, and the file must stay as it was.
    final f = File('${tmp.path}/broken.mp3')
      ..writeAsBytesSync(List.filled(64, 9));
    final before = f.readAsBytesSync();
    await expectLater(
      writeTagValues(f.path, const TagEdit(title: 'x')),
      throwsA(isA<TagEditException>()),
    );
    expect(f.readAsBytesSync(), before);
    expect(File('${f.path}.nslbak').existsSync(), isFalse);
  });
}
