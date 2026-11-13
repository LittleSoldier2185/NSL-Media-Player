import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import 'media_types.dart';

/// Formats whose tags can be written back (what `audio_metadata_reader`'s
/// writers handle). OGG and AAC can be played but not edited.
const editableExtensions = {'mp3', 'flac', 'm4a', 'wav'};

/// Biggest cover picture accepted (a huge one would bloat every copy of the
/// song).
const maxCoverBytes = 8 * 1024 * 1024;

bool canEditTags(String path) => editableExtensions.contains(extensionOf(path));

/// What a song's tags hold right now.
class TagValues {
  const TagValues({
    this.title = '',
    this.artist = '',
    this.album = '',
    this.cover,
  });

  final String title;
  final String artist;
  final String album;

  /// The embedded picture's bytes, or null.
  final Uint8List? cover;
}

/// Changes to make. A null field is left as it is; an empty string clears it.
class TagEdit {
  const TagEdit({
    this.title,
    this.artist,
    this.album,
    this.cover,
    this.removeCover = false,
  });

  final String? title;
  final String? artist;
  final String? album;

  /// A new cover (JPEG or PNG bytes).
  final Uint8List? cover;

  /// Take the cover out (ignored when [cover] is given).
  final bool removeCover;

  bool get isEmpty =>
      title == null &&
      artist == null &&
      album == null &&
      cover == null &&
      !removeCover;
}

/// Why a song could not be changed; [message] is fit to show.
class TagEditException implements Exception {
  TagEditException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// "image/jpeg" or "image/png" from the bytes, or null for anything else.
String? coverMimeType(Uint8List b) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (b.length > 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47) {
    return 'image/png';
  }
  return null;
}

/// Reads the tags of [path] (in another isolate: tags of big files take a
/// moment). Returns empty values for a file with no readable tags.
Future<TagValues> readTagValues(String path) => Isolate.run(() {
  try {
    final m = readMetadata(File(path), getImage: true);
    return TagValues(
      title: m.title?.trim() ?? '',
      artist: m.artist?.trim() ?? '',
      album: m.album?.trim() ?? '',
      cover: m.pictures.isEmpty ? null : m.pictures.first.bytes,
    );
  } on Object {
    return const TagValues();
  }
});

/// Writes [edit] into the song file [path].
///
/// The file is copied to `<name>.nslbak` first and the result is read back;
/// if the new tags are not what was asked for (or anything goes wrong) the
/// original is put back, so a failed edit never leaves a damaged song. Throws
/// [TagEditException] with a readable reason.
Future<void> writeTagValues(String path, TagEdit edit) async {
  if (edit.isEmpty) return;
  if (!canEditTags(path)) {
    throw TagEditException(
      'Tags of .${extensionOf(path)} files cannot be edited '
      '(supported: ${editableExtensions.join(', ')}).',
    );
  }
  final cover = edit.cover;
  if (cover != null) {
    if (coverMimeType(cover) == null) {
      throw TagEditException('The cover must be a JPG or PNG picture.');
    }
    if (cover.length > maxCoverBytes) {
      throw TagEditException('The cover picture is too big (over 8 MB).');
    }
  }
  final error = await Isolate.run(() => _write(path, edit));
  if (error != null) throw TagEditException(error);
}

/// Does the work; returns an error message, or null on success.
String? _write(String path, TagEdit edit) {
  final file = File(path);
  final backup = File('$path.nslbak');
  try {
    if (!file.existsSync()) return 'The file is missing.';
    if (backup.existsSync()) backup.deleteSync();
    file.copySync(backup.path);
  } on FileSystemException catch (e) {
    return 'Could not make a safety copy: ${e.message}';
  }

  String? fail;
  try {
    updateMetadata(file, (m) {
      if (edit.title != null) m.setTitle(_orNull(edit.title!));
      if (edit.artist != null) m.setArtist(_orNull(edit.artist!));
      if (edit.album != null) m.setAlbum(_orNull(edit.album!));
      final cover = edit.cover;
      if (cover != null) {
        m.setPictures([
          Picture(cover, coverMimeType(cover)!, PictureType.coverFront),
        ]);
      } else if (edit.removeCover) {
        m.setPictures(const []);
      }
    });
    fail = _check(file, edit);
  } on FileSystemException catch (e) {
    fail =
        'The file is in use or read-only (stop playing it first): '
        '${e.osError?.message ?? e.message}';
  } on Object catch (e) {
    fail = 'Could not write the tags: $e';
  }

  if (fail == null) {
    try {
      backup.deleteSync();
    } on Object {
      // a leftover safety copy is harmless
    }
    return null;
  }
  try {
    backup.copySync(path);
    backup.deleteSync();
  } on Object {
    return '$fail The original is kept at ${backup.path}.';
  }
  return fail;
}

String? _orNull(String s) {
  final t = s.trim();
  return t.isEmpty ? null : t;
}

/// Reads the file back and compares it with what was asked for.
String? _check(File file, TagEdit edit) {
  final m = readMetadata(file, getImage: true);
  bool same(String? want, String? got) =>
      (_orNull(want ?? '') ?? '') == (got?.trim() ?? '');
  if (edit.title != null && !same(edit.title, m.title)) {
    return 'The title was not saved.';
  }
  if (edit.artist != null && !same(edit.artist, m.artist)) {
    return 'The artist was not saved.';
  }
  if (edit.album != null && !same(edit.album, m.album)) {
    return 'The album was not saved.';
  }
  if (edit.cover != null &&
      (m.pictures.isEmpty ||
          m.pictures.first.bytes.length != edit.cover!.length)) {
    return 'The cover was not saved.';
  }
  if (edit.cover == null && edit.removeCover && m.pictures.isNotEmpty) {
    return 'The cover was not removed.';
  }
  return null;
}
