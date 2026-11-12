import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_types.dart';
import 'thumbnail_service.dart';

/// One file in the library with its tags.
class LibraryItem {
  LibraryItem({
    required this.path,
    required this.title,
    this.artist = '',
    this.album = '',
    this.durationMs = 0,
    required this.modified,
    this.taken,
  });

  final String path;
  final String title;
  final String artist;
  final String album;
  final int durationMs;

  /// File modification time (ms since epoch); used for "Recently added" and
  /// to know when tags must be re-read.
  final int modified;

  /// When a picture was taken (ms since epoch, from its EXIF data), or null.
  final int? taken;

  /// When it was taken, or else when the file was last changed.
  int get when => taken ?? modified;

  bool get isVideo => videoExtensions.contains(extensionOf(path));

  /// Audio, video, image or PDF (an unknown extension counts as audio, the
  /// kind the index held before pictures and books were added).
  MediaKind get kind => kindOf(path) ?? MediaKind.audio;

  /// Can be played (audio or video).
  bool get isPlayable => kind == MediaKind.audio || kind == MediaKind.video;

  Map<String, dynamic> toJson() => {
    'p': path,
    't': title,
    'a': artist,
    'b': album,
    'd': durationMs,
    'm': modified,
    if (taken != null) 'k': taken,
  };

  static LibraryItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final p = j['p'], t = j['t'], m = j['m'];
    if (p is! String || t is! String || m is! int) return null;
    return LibraryItem(
      path: p,
      title: t,
      artist: j['a'] is String ? j['a'] as String : '',
      album: j['b'] is String ? j['b'] as String : '',
      durationMs: j['d'] is int ? j['d'] as int : 0,
      modified: m,
      taken: j['k'] is int ? j['k'] as int : null,
    );
  }
}

/// Songs that share an album name (and folder), as shown on Home > Music.
class Album {
  Album({
    required this.name,
    required this.artist,
    required this.tracks,
    required this.newest,
  });

  final String name;

  /// The one artist, or "Various artists" when the tracks differ.
  final String artist;

  /// In file-name order, which is track order for most libraries.
  final List<LibraryItem> tracks;

  /// Most recent modification time among the tracks (for "recently added").
  final int newest;

  /// The first track stands in for the album's cover art.
  LibraryItem get cover => tracks.first;
}

enum LibrarySort { title, artist, album, recent }

/// Library folders, a scanned index of their media files, and cover art.
///
/// The index is cached in a JSON file so the library appears instantly on the
/// next start; a rescan only re-reads tags of new or changed files.
class LibraryService extends ChangeNotifier {
  /// [indexFile] overrides where the index is cached (used by tests).
  LibraryService(
    this._prefs, {
    File? indexFile,
    ThumbnailService? thumbnails,
    bool autoRescan = true,
  }) : _indexOverride = indexFile,
       thumbnails = thumbnails ?? ThumbnailService() {
    _folders.addAll(_prefs.getStringList('libraryFolders') ?? const []);
    _loadIndex();
    // An index from before pictures and PDFs were kept does not know about
    // them: look through the folders once more, in the background.
    if (autoRescan &&
        _folders.isNotEmpty &&
        (_prefs.getInt(_kindsKey) ?? 0) < _kindsVersion) {
      scheduleMicrotask(scan);
    }
  }

  static const _kindsKey = 'libraryKindsVersion';
  static const _kindsVersion = 2;

  final SharedPreferences _prefs;
  final File? _indexOverride;

  /// Preview pictures (cover art / video frames) for the files in the library.
  final ThumbnailService thumbnails;
  final List<String> _folders = [];

  /// Every file in the library folders: music, video, pictures and PDFs.
  List<LibraryItem> _all = [];

  /// Only what can be played (music and video). Everything that lists or
  /// plays media uses this, so pictures and books never reach the play queue.
  List<LibraryItem> _items = [];

  bool scanning = false;
  int scanned = 0;
  int scanTotal = 0;

  List<String> get folders => List.unmodifiable(_folders);
  List<LibraryItem> get items => _items;

  /// Pictures in the library folders (newest first).
  List<LibraryItem> get images => _ofKind(MediaKind.image);

  /// PDF books in the library folders (by title).
  List<LibraryItem> get books => _ofKind(MediaKind.pdf);

  int get imageCount => _all.where((i) => i.kind == MediaKind.image).length;
  int get bookCount => _all.where((i) => i.kind == MediaKind.pdf).length;

  List<LibraryItem> _ofKind(MediaKind k) {
    final out = [
      for (final i in _all)
        if (i.kind == k) i,
    ];
    out.sort(
      k == MediaKind.image
          ? (a, b) => b.when.compareTo(a.when)
          : (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return out;
  }

  void _setAll(List<LibraryItem> all) {
    _all = all;
    _items = [
      for (final i in all)
        if (i.isPlayable) i,
    ];
  }

  // ---- folders ----

  /// Drops trailing separators so `C:\Music\` and `C:\Music` are the same.
  static String _norm(String dir) {
    var d = dir;
    while (d.length > 3 && (d.endsWith('\\') || d.endsWith('/'))) {
      d = d.substring(0, d.length - 1);
    }
    return d;
  }

  /// True when [path] is inside [dir] (case-insensitive, whole segments only,
  /// so `C:\Music2\a.mp3` is not inside `C:\Music`).
  static bool isUnder(String path, String dir) {
    final d = _norm(dir).toLowerCase();
    final p = path.toLowerCase();
    final base = d.endsWith('\\') || d.endsWith('/') ? d : '$d\\';
    return p.startsWith(base) || p.startsWith(base.replaceAll('\\', '/'));
  }

  /// Last path segment, for showing a short folder name.
  static String folderName(String dir) {
    final n = fileNameOf(_norm(dir));
    return n.isEmpty ? dir : n;
  }

  /// Number of library files inside [dir].
  int countIn(String dir) => _items.where((i) => isUnder(i.path, dir)).length;

  /// Saves [dir] to the library and scans it. Returns false if it was
  /// already saved.
  Future<bool> addFolder(String dir) async {
    final d = _norm(dir);
    if (_folders.any((f) => f.toLowerCase() == d.toLowerCase())) return false;
    _folders.add(d);
    _prefs.setStringList('libraryFolders', _folders);
    notifyListeners();
    await scan();
    return true;
  }

  Future<void> removeFolder(String dir) async {
    _folders.remove(dir);
    _prefs.setStringList('libraryFolders', _folders);
    // Keep files that another saved folder still covers.
    _setAll([
      for (final i in _all)
        if (_folders.any((f) => isUnder(i.path, f))) i,
    ]);
    await _saveIndex();
    notifyListeners();
  }

  // ---- index file ----

  File? get _indexFile {
    if (_indexOverride != null) return _indexOverride;
    final base = Platform.environment['APPDATA'];
    if (base == null) return null;
    return File('$base\\NSL Media Player\\library.json');
  }

  void _loadIndex() {
    try {
      final f = _indexFile;
      if (f == null || !f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync());
      if (j is List) {
        _setAll(j.map(LibraryItem.fromJson).whereType<LibraryItem>().toList());
      }
    } on Object catch (e) {
      debugPrint('Could not read library index: $e');
    }
  }

  Future<void> _saveIndex() async {
    try {
      final f = _indexFile;
      if (f == null) return;
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(_all.map((i) => i.toJson()).toList()));
    } on Object catch (e) {
      debugPrint('Could not write library index: $e');
    }
  }

  // ---- scanning ----

  /// Walks every library folder, reading tags for new or changed files only.
  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    scanned = 0;
    scanTotal = 0;
    notifyListeners();
    try {
      final known = {for (final i in _all) i.path: i};
      final found = <File>[];
      final seen = <String>{}; // overlapping folders must not list a file twice
      for (final dir in _folders) {
        await for (final e in Directory(
          dir,
        ).list(recursive: true, followLinks: false).handleError((_) {})) {
          if (e is File &&
              isLibraryFile(e.path) &&
              seen.add(e.path.toLowerCase())) {
            found.add(e);
          }
        }
      }
      scanTotal = found.length;
      notifyListeners();

      final result = <LibraryItem>[];
      for (final f in found) {
        final modified = (await f.lastModified()).millisecondsSinceEpoch;
        final old = known[f.path];
        result.add(
          old != null && old.modified == modified
              ? old
              : await _readItem(f, modified),
        );
        scanned++;
        // Yield regularly so the UI stays responsive on big libraries.
        if (scanned % 20 == 0) {
          notifyListeners();
          await Future<void>.delayed(Duration.zero);
        }
      }
      _setAll(result);
      await _prefs.setInt(_kindsKey, _kindsVersion);
      await _saveIndex();
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  Future<LibraryItem> _readItem(File f, int modified) async {
    if (kindOf(f.path) != MediaKind.image) return _read(f, modified);
    return LibraryItem(
      path: f.path,
      title: _stripExt(fileNameOf(f.path)),
      modified: modified,
      taken: (await readTakenDate(f))?.millisecondsSinceEpoch,
    );
  }

  /// When the picture was taken, from the EXIF data at the start of the file.
  /// Null for pictures without it (PNG, screenshots) or unreadable files.
  static Future<DateTime?> readTakenDate(File f) async {
    try {
      final bytes = <int>[];
      // EXIF sits at the start of the file; no need to read the whole picture.
      await for (final chunk in f.openRead(0, 128 * 1024)) {
        bytes.addAll(chunk);
      }
      final tags = await readExifFromBytes(bytes);
      final raw =
          tags['EXIF DateTimeOriginal'] ??
          tags['EXIF DateTimeDigitized'] ??
          tags['Image DateTime'];
      return raw == null ? null : parseExifDate(raw.printable);
    } on Object {
      return null;
    }
  }

  /// Reads `2026:11:08 16:42:11` (local time, as cameras write it).
  static DateTime? parseExifDate(String s) {
    final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})')
        .firstMatch(s.trim());
    if (m == null) return null;
    final v = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
    if (v[0] < 1900 || v[1] < 1 || v[1] > 12 || v[2] < 1 || v[2] > 31) {
      return null;
    }
    return DateTime(v[0], v[1], v[2], v[3], v[4], v[5]);
  }

  LibraryItem _read(File f, int modified) {
    final fallback = _stripExt(fileNameOf(f.path));
    // Everything but music is listed by file name; only audio tags are read
    // (picture and book details come with the viewers).
    final kind = kindOf(f.path);
    if (kind != null && kind != MediaKind.audio) {
      return LibraryItem(path: f.path, title: fallback, modified: modified);
    }
    try {
      final m = readMetadata(f, getImage: false);
      final title = m.title?.trim();
      return LibraryItem(
        path: f.path,
        title: title == null || title.isEmpty ? fallback : title,
        artist: m.artist?.trim() ?? '',
        album: m.album?.trim() ?? '',
        durationMs: m.duration?.inMilliseconds ?? 0,
        modified: modified,
      );
    } on Object {
      // Unsupported or corrupt tags: still list the file.
      return LibraryItem(path: f.path, title: fallback, modified: modified);
    }
  }

  static String _stripExt(String name) {
    final i = name.lastIndexOf('.');
    return i > 0 ? name.substring(0, i) : name;
  }

  // ---- query ----

  /// Items matching [query] (title / artist / album / file name) in [sort] order.
  List<LibraryItem> query({
    String query = '',
    bool? video, // null = all, true = videos, false = music
    String? folder, // null = every saved folder
    LibrarySort sort = LibrarySort.title,
  }) {
    final q = query.trim().toLowerCase();
    final out = [
      for (final i in _items)
        if ((video == null || i.isVideo == video) &&
            (folder == null || isUnder(i.path, folder)) &&
            (q.isEmpty ||
                i.title.toLowerCase().contains(q) ||
                i.artist.toLowerCase().contains(q) ||
                i.album.toLowerCase().contains(q) ||
                fileNameOf(i.path).toLowerCase().contains(q)))
          i,
    ];
    int cmp(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    out.sort(switch (sort) {
      LibrarySort.title => (a, b) => cmp(a.title, b.title),
      LibrarySort.artist => (a, b) {
        final c = cmp(a.artist, b.artist);
        return c != 0 ? c : cmp(a.title, b.title);
      },
      LibrarySort.album => (a, b) {
        final c = cmp(a.album, b.album);
        return c != 0 ? c : cmp(a.title, b.title);
      },
      LibrarySort.recent => (a, b) => b.modified.compareTo(a.modified),
    });
    return out;
  }

  /// Albums found in the tags of the music files, newest first. Songs without
  /// an album tag are not part of any album.
  List<Album> albums() {
    final cached = _albumsCache;
    if (cached != null && identical(_albumsFor, _items)) return cached;
    final groups = <String, List<LibraryItem>>{};
    for (final i in _items) {
      if (i.isVideo || i.album.trim().isEmpty) continue;
      final slash = i.path.lastIndexOf(RegExp(r'[\\/]'));
      final dir = slash < 0 ? '' : i.path.substring(0, slash);
      groups
          .putIfAbsent(
            '${i.album.toLowerCase()}|${dir.toLowerCase()}',
            () => [],
          )
          .add(i);
    }
    final out = <Album>[];
    for (final tracks in groups.values) {
      tracks.sort(
        (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
      );
      final artists = {
        for (final t in tracks)
          if (t.artist.trim().isNotEmpty) t.artist.trim(),
      };
      out.add(
        Album(
          name: tracks.first.album.trim(),
          artist: artists.length == 1
              ? artists.first
              : artists.isEmpty
              ? ''
              : 'Various artists',
          tracks: tracks,
          newest: tracks.map((t) => t.modified).reduce((a, b) => a > b ? a : b),
        ),
      );
    }
    out.sort((a, b) => b.newest.compareTo(a.newest));
    _albumsCache = out;
    _albumsFor = _items;
    return out;
  }

  List<Album>? _albumsCache;
  List<LibraryItem>? _albumsFor;

  /// Number of different artists in the music tags.
  int get artistCount => {
    for (final i in _items)
      if (!i.isVideo && i.artist.trim().isNotEmpty)
        i.artist.trim().toLowerCase(),
  }.length;

  /// Replaces the index without scanning (tests).
  @visibleForTesting
  void setItemsForTest(List<LibraryItem> items) {
    _setAll(items);
    notifyListeners();
  }

  int get musicCount => _items.where((i) => !i.isVideo).length;
  int get videoCount => _items.where((i) => i.isVideo).length;

  // ---- view mode ----

  /// Library shown as a grid of thumbnails instead of a list.
  bool get gridView => _prefs.getBool('libraryGrid') ?? false;

  set gridView(bool v) {
    _prefs.setBool('libraryGrid', v);
    notifyListeners();
  }
}
