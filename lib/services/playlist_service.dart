import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A named, ordered list of files. Files may come from any folder: a playlist
/// stores plain paths and does not depend on the saved library folders.
class Playlist {
  Playlist({
    required this.id,
    required this.name,
    List<String>? paths,
    DateTime? updated,
  }) : paths = paths ?? [],
       updated = updated ?? DateTime.now();

  final String id;
  String name;
  final List<String> paths;
  DateTime updated;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'paths': paths,
    'updated': updated.millisecondsSinceEpoch,
  };

  static Playlist? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], paths = j['paths'];
    if (id is! String || name is! String || paths is! List) return null;
    final t = j['updated'];
    return Playlist(
      id: id,
      name: name,
      paths: [
        for (final p in paths)
          if (p is String) p,
      ],
      updated: t is int ? DateTime.fromMillisecondsSinceEpoch(t) : null,
    );
  }
}

/// Saved playlists, stored in `%APPDATA%\NSL Media Player\playlists.json`.
class PlaylistService extends ChangeNotifier {
  /// [file] overrides the storage location (used by tests). The same class
  /// keeps photo albums: they are named lists of files too, just stored in
  /// their own file ([fileName]) and named "New album" by default.
  PlaylistService({
    File? file,
    this.fileName = 'playlists.json',
    this.defaultName = 'New playlist',
  }) : _fileOverride = file {
    _load();
  }

  final String fileName;
  final String defaultName;
  final File? _fileOverride;
  final List<Playlist> _lists = [];
  int _seq = 0;

  List<Playlist> get all => List.unmodifiable(_lists);

  Playlist? byId(String id) {
    for (final p in _lists) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ---- persistence ----

  File? get _file {
    if (_fileOverride != null) return _fileOverride;
    final base = Platform.environment['APPDATA'];
    return base == null ? null : File('$base\\NSL Media Player\\$fileName');
  }

  void _load() {
    try {
      final f = _file;
      if (f == null || !f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync());
      if (j is List) {
        _lists.addAll(j.map(Playlist.fromJson).whereType<Playlist>());
      }
    } on Object catch (e) {
      debugPrint('Could not read playlists: $e');
    }
  }

  void _save() {
    try {
      final f = _file;
      if (f != null) {
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(jsonEncode(_lists.map((p) => p.toJson()).toList()));
      }
    } on Object catch (e) {
      debugPrint('Could not write playlists: $e');
    }
    notifyListeners();
  }

  // ---- editing ----

  static List<String> _dedupe(Iterable<String> paths) {
    final seen = <String>{};
    return [
      for (final p in paths)
        if (seen.add(p.toLowerCase())) p,
    ];
  }

  /// [wanted] if free, otherwise "wanted (2)", "wanted (3)", ...
  /// [except] is a playlist that may keep its own name (for renaming).
  String uniqueName(String wanted, {String? except}) {
    final base = wanted.trim().isEmpty ? defaultName : wanted.trim();
    bool taken(String n) => _lists.any(
      (p) => p.id != except && p.name.toLowerCase() == n.toLowerCase(),
    );
    if (!taken(base)) return base;
    for (var i = 2; ; i++) {
      final n = '$base ($i)';
      if (!taken(n)) return n;
    }
  }

  /// Creates a playlist from [paths] (duplicates are dropped, order is kept).
  Playlist create(String name, [Iterable<String> paths = const []]) {
    final p = Playlist(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
      name: uniqueName(name),
      paths: _dedupe(paths),
    );
    _lists.add(p);
    _save();
    return p;
  }

  /// Appends [paths] that are not already in the playlist. Returns how many
  /// were added.
  int addPaths(String id, Iterable<String> paths) {
    final pl = byId(id);
    if (pl == null) return 0;
    final have = {for (final p in pl.paths) p.toLowerCase()};
    var added = 0;
    for (final path in paths) {
      if (have.add(path.toLowerCase())) {
        pl.paths.add(path);
        added++;
      }
    }
    if (added > 0) {
      pl.updated = DateTime.now();
      _save();
    }
    return added;
  }

  void rename(String id, String name) {
    final pl = byId(id);
    if (pl == null) return;
    pl.name = uniqueName(name, except: id);
    pl.updated = DateTime.now();
    _save();
  }

  void delete(String id) {
    _lists.removeWhere((p) => p.id == id);
    _save();
  }

  void removeAt(String id, int index) {
    final pl = byId(id);
    if (pl == null || index < 0 || index >= pl.paths.length) return;
    pl.paths.removeAt(index);
    pl.updated = DateTime.now();
    _save();
  }

  /// Moves the item at [oldIndex] so it ends up at [newIndex] (its final
  /// position, as [ReorderableListView.onReorderItem] reports it).
  void move(String id, int oldIndex, int newIndex) {
    final pl = byId(id);
    if (pl == null || oldIndex < 0 || oldIndex >= pl.paths.length) return;
    newIndex = newIndex.clamp(0, pl.paths.length - 1);
    if (newIndex == oldIndex) return;
    pl.paths.insert(newIndex, pl.paths.removeAt(oldIndex));
    pl.updated = DateTime.now();
    _save();
  }
}
