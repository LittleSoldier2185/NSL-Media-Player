import 'dart:io';
import 'dart:typed_data';

/// A tiny but valid JPEG header + filler (enough for the tag code, which only
/// checks the magic bytes).
Uint8List jpeg([int n = 300]) =>
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(n, 7)]);

Uint8List png() => Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  1,
  2,
  3,
]);

/// An MP3 with an ID3v2.3 tag holding [title], followed by silent frames.
File makeMp3(Directory d, String name, {String title = 'Old title'}) {
  List<int> frame(String id, String text) {
    final body = [0, ...text.codeUnits];
    return [...id.codeUnits, 0, 0, 0, body.length, 0, 0, ...body];
  }

  final frames = [
    ...frame('TIT2', title),
    ...frame('TPE1', 'Old artist'),
    ...frame('TALB', 'Old album'),
  ];
  final size = frames.length;
  final header = [
    ...'ID3'.codeUnits,
    3,
    0,
    0,
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
  ];
  // MPEG-1 Layer III, 128 kbps, 44.1 kHz: 417-byte frames.
  final audio = <int>[];
  for (var i = 0; i < 6; i++) {
    audio.addAll([0xFF, 0xFB, 0x90, 0x00, ...List.filled(413, 0)]);
  }
  final f = File('${d.path}${Platform.pathSeparator}$name');
  f.writeAsBytesSync([...header, ...frames, ...audio]);
  return f;
}
