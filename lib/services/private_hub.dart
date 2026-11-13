import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../player_controller/player_controller.dart';
import 'book_service.dart';
import 'history_service.dart';
import 'library_service.dart';
import 'playlist_service.dart';
import 'private_service.dart';
import 'thumbnail_service.dart';

/// Everything that belongs to Private mode, kept apart from the normal app:
/// its own library index, folders, playlists, albums, book places and
/// thumbnail cache. The normal library skips whatever is private.
class PrivateHub {
  PrivateHub._(
    this.lock,
    this.library,
    this.playlists,
    this.albums,
    this.books,
  );

  /// The PIN, the lock and the list of private files.
  final PrivateService lock;

  /// Only the private folders and files (the same views show it).
  final LibraryService library;
  final PlaylistService playlists;
  final PlaylistService albums;
  final BookService books;

  /// For tests: a hub around the given parts, with [normal] as the library.
  PrivateHub.forTest({
    required this.lock,
    required this.library,
    required this.playlists,
    required this.albums,
    required this.books,
    required LibraryService normal,
  }) : _normal = normal;

  /// The normal library, which must not list private files.
  late final LibraryService _normal;

  Set<String> _foldersSeen = {};
  Set<String> _filesSeen = {};

  /// Builds the hub and the normal [LibraryService] that goes with it (the
  /// normal one has to know what to leave out).
  static (PrivateHub, LibraryService) create(
    SharedPreferences prefs, {
    bool autoRescan = true,
  }) {
    final lock = PrivateService();
    final normal = LibraryService(
      prefs,
      autoRescan: autoRescan,
      excluded: lock.isPrivate,
    );
    final base = Platform.environment['APPDATA'];
    final library = LibraryService(
      prefs,
      autoRescan: autoRescan,
      foldersKey: 'privateFolders',
      indexName: 'private_index.json',
      extraFiles: () => lock.taggedFiles,
      thumbnails: ThumbnailService(
        dir: base == null
            ? null
            : Directory('$base\\NSL Media Player\\thumbs_private'),
      ),
    );
    lock.folders = () => library.folders;
    final hub = PrivateHub._(
      lock,
      library,
      PlaylistService(
        fileName: 'private_playlists.json',
        defaultName: 'New playlist',
      ),
      PlaylistService(
        fileName: 'private_albums.json',
        defaultName: 'New album',
      ),
      BookService(fileName: 'private_books.json'),
    );
    hub._normal = normal;
    hub._foldersSeen = {for (final f in library.folders) f.toLowerCase()};
    hub._filesSeen = {for (final f in lock.taggedFiles) f.toLowerCase()};
    library.addListener(hub._onChanged);
    lock.addListener(hub._onChanged);
    return (hub, normal);
  }

  /// Connects the player and history: private files leave no trace there, and
  /// locking stops them and drops their thumbnails.
  void attach(NslPlayerController controller, HistoryService history) {
    controller.isPrivate = lock.isPrivate;
    history.isPrivate = lock.isPrivate;
    lock.onLocked = () {
      controller.dropPrivate();
      library.thumbnails.clearCache();
    };
  }

  /// A folder or file became private (or stopped being): the normal library
  /// forgets it, or finds it again.
  bool _resetting = false;

  void _onChanged() {
    if (_resetting) return;
    final folders = {for (final f in library.folders) f.toLowerCase()};
    final files = {for (final f in lock.taggedFiles) f.toLowerCase()};
    final foldersChanged =
        folders.length != _foldersSeen.length ||
        !folders.containsAll(_foldersSeen);
    final filesChanged =
        files.length != _filesSeen.length || !files.containsAll(_filesSeen);
    if (!foldersChanged && !filesChanged) return;
    final removed =
        !folders.containsAll(_foldersSeen) || !files.containsAll(_filesSeen);
    _foldersSeen = folders;
    _filesSeen = files;
    if (filesChanged) library.scan();
    if (removed) {
      _normal.scan(); // what left Private is part of the normal library again
    } else {
      _normal.applyExclusions();
    }
  }

  /// Forgot the PIN: forgets the PIN and everything private (files are not
  /// touched); what was private goes back to the normal library.
  Future<void> reset() async {
    for (final p in List.of(playlists.all)) {
      playlists.delete(p.id);
    }
    for (final a in List.of(albums.all)) {
      albums.delete(a.id);
    }
    await books.clear();
    await library.thumbnails.clearCache();
    _resetting = true;
    try {
      lock.resetAll();
      await library.clearAll();
      _foldersSeen = {};
      _filesSeen = {};
    } finally {
      _resetting = false;
    }
    while (_normal.scanning) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await _normal.scan();
  }
}
